import hashlib
import json
import os
import re
from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Sequence

import torch

from constraint_rag import extract_json, format_passage, passage_to_title_text
from model_rag import ModelRAG


@dataclass
class BM25FilterConfig:
    final_k: int = 3


@dataclass
class RelevanceFilterConfig:
    final_k: int = 3
    relevance_max_new_tokens: int = 24
    generation_batch_size: int = 8
    bm25_tie_break_weight: float = 1e-6


@dataclass
class RankedPassage:
    passage: Any
    bm25_score: float
    score: float


def build_short_answer_prompt(query: str, passages: Sequence[Any]) -> str:
    context = "\n".join(format_passage(passage) for passage in passages)
    return (
        "Answer the question using only the passages. "
        "Write only the short answer, with no explanation.\n"
        f"{context}\n"
        f"Question: {query}\n"
        "Answer:"
    )


class BM25FilteredRAG(ModelRAG):
    """A BM25-only passage-filtering baseline."""

    def __init__(self, config: Optional[BM25FilterConfig] = None):
        super().__init__()
        self.config = config or BM25FilterConfig()

    def make_augmented_inputs_for_generate(self, queries, qids, k=5):
        list_passages, list_scores = self.search(queries, qids, k=k)
        prompts = []
        for query, passages, scores in zip(queries, list_passages, list_scores):
            ranked = sorted(
                zip(passages, scores),
                key=lambda item: float(item[1]),
                reverse=True,
            )
            selected = [passage for passage, _ in ranked[: self.config.final_k]]
            prompts.append(build_short_answer_prompt(query, selected))
        return prompts


class RelevanceOnlyRAG(ModelRAG):
    """A scalar relevance ablation without constraint-wise diagnostics."""

    def __init__(
        self,
        config: Optional[RelevanceFilterConfig] = None,
        cache_path: Optional[str] = None,
    ):
        super().__init__()
        self.config = config or RelevanceFilterConfig()
        self.cache_path = cache_path
        self.cache: Dict[str, Any] = {}
        if cache_path and os.path.exists(cache_path):
            with open(cache_path, "r") as f:
                for line in f:
                    record = json.loads(line)
                    self.cache[record["key"]] = record["value"]

    def _cache_key(self, query: str, passage: Any) -> str:
        _, passage_text = passage_to_title_text(passage)
        payload = json.dumps(["relevance", query, passage_text], sort_keys=True, ensure_ascii=False)
        return hashlib.sha1(payload.encode("utf-8")).hexdigest()

    def _set_cache(self, key: str, value: Any) -> None:
        self.cache[key] = value
        if self.cache_path is None:
            return
        with open(self.cache_path, "a") as f:
            f.write(json.dumps({"key": key, "value": value}, ensure_ascii=False) + "\n")

    def _model_device(self):
        device = getattr(self.model, "device", None)
        if device is not None:
            return device
        try:
            return next(self.model.parameters()).device
        except (AttributeError, StopIteration):
            return torch.device("cpu")

    def _generate_texts(self, prompts: Sequence[str], max_new_tokens: int) -> List[str]:
        if not prompts:
            return []
        outputs_text = []
        device = self._model_device()
        batch_size = max(int(self.config.generation_batch_size), 1)
        kwargs = {"max_new_tokens": max_new_tokens, "do_sample": False}
        if getattr(self.tokenizer, "eos_token_id", None) is not None:
            kwargs["pad_token_id"] = self.tokenizer.eos_token_id

        for start in range(0, len(prompts), batch_size):
            batch_prompts = list(prompts[start:start + batch_size])
            inputs = self.tokenizer(batch_prompts, return_tensors="pt", padding=True, truncation=True)
            inputs = {key: value.to(device) for key, value in inputs.items()}
            outputs = self.model.generate(**inputs, **kwargs)
            new_tokens = outputs[:, inputs["input_ids"].shape[1]:]
            outputs_text.extend(self.tokenizer.batch_decode(new_tokens, skip_special_tokens=True, clean_up_tokenization_spaces=False))
        return outputs_text

    def build_relevance_prompt(self, query: str, passage: Any) -> str:
        return (
            "Decide whether the passage contains useful evidence for answering the question. "
            "Return JSON only as {\"relevance\": 0 or 1}.\n"
            f"Question: {query}\n"
            f"{format_passage(passage)}\n"
            "JSON:"
        )

    def parse_relevance_score(self, text: str) -> float:
        data = extract_json(text)
        if isinstance(data, dict):
            for key in ("relevance", "score", "relevant"):
                if key not in data:
                    continue
                value = data[key]
                if isinstance(value, bool):
                    return 1.0 if value else 0.0
                try:
                    return max(0.0, min(float(value), 1.0))
                except (TypeError, ValueError):
                    value = str(value).strip().lower()
                    if value in {"yes", "true", "relevant", "useful", "support"}:
                        return 1.0
                    if value in {"no", "false", "irrelevant", "not_relevant", "unrelated"}:
                        return 0.0
        text = text.strip().lower()
        number = re.search(r"(?:relevance|score)\D*([01](?:\.\d+)?)", text)
        if number:
            return max(0.0, min(float(number.group(1)), 1.0))
        if any(word in text for word in ("yes", "relevant", "useful", "support")):
            return 1.0
        return 0.0

    def score_passages(self, query: str, passages: Sequence[Any], bm25_scores: Sequence[float]) -> List[RankedPassage]:
        results: List[Optional[float]] = [None] * len(passages)
        uncached_indices = []
        prompts = []
        for index, passage in enumerate(passages):
            key = self._cache_key(query, passage)
            if key in self.cache:
                results[index] = float(self.cache[key])
            else:
                uncached_indices.append(index)
                prompts.append(self.build_relevance_prompt(query, passage))

        texts = self._generate_texts(prompts, max_new_tokens=self.config.relevance_max_new_tokens)
        for index, text in zip(uncached_indices, texts):
            score = self.parse_relevance_score(text)
            self._set_cache(self._cache_key(query, passages[index]), score)
            results[index] = score

        ranked = []
        for passage, bm25_score, relevance_score in zip(passages, bm25_scores, results):
            relevance_score = float(relevance_score or 0.0)
            score = relevance_score + self.config.bm25_tie_break_weight * float(bm25_score)
            ranked.append(RankedPassage(passage=passage, bm25_score=float(bm25_score), score=score))
        return sorted(ranked, key=lambda item: item.score, reverse=True)

    def make_augmented_inputs_for_generate(self, queries, qids, k=5):
        list_passages, list_scores = self.search(queries, qids, k=k)
        prompts = []
        for query, passages, scores in zip(queries, list_passages, list_scores):
            ranked = self.score_passages(query, passages, scores)
            selected = [item.passage for item in ranked[: self.config.final_k]]
            prompts.append(build_short_answer_prompt(query, selected))
        return prompts
