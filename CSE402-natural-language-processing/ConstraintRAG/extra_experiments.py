import json
import os
from dataclasses import dataclass
from typing import Any, Dict, Iterable, List, Sequence

import torch

from constraint_rag import (
    extract_answer_from_json,
    extract_first_answer_candidate,
    get_evidence_candidates_text,
    strip_evidence_candidates,
)
from utils.metrics import best_subspan_exact_match


class ScoreOverrideHit:
    """Proxy a Lucene hit while overriding the score used by RAG wrappers."""

    def __init__(self, hit: Any, score: float):
        self._hit = hit
        self.score = float(score)
        self.lucene_document = hit.lucene_document

    def __getattr__(self, name: str) -> Any:
        return getattr(self._hit, name)


@dataclass
class HardNegativeSearcher:
    """Inject lower-ranked BM25 hits into top retrieval slots for robustness tests."""

    base_searcher: Any
    inject_count: int = 2
    pool_k: int = 30

    def search(self, query: str, k: int):
        pool_k = max(int(self.pool_k), int(k) + int(self.inject_count))
        hits = list(self.base_searcher.search(query, pool_k))
        if len(hits) <= k or self.inject_count <= 0:
            return hits[:k]

        inject_count = min(int(self.inject_count), k, max(len(hits) - k, 0))
        keep_count = max(k - inject_count, 0)
        hard_negatives = hits[k:k + inject_count]
        kept_hits = hits[:keep_count]

        injected = []
        for slot, hit in enumerate(hard_negatives):
            score_source = hits[slot] if slot < len(hits) else hit
            injected.append(ScoreOverrideHit(hit, getattr(score_source, "score", getattr(hit, "score", 0.0))))
        return injected + kept_hits


def metric_value(value):
    return value.item() if hasattr(value, "item") else float(value)


def compute_rag_metrics(predictions: Sequence[str], answers: Sequence[Sequence[str]], rouge, metadata: Dict[str, Any]):
    accuracy = best_subspan_exact_match(predictions, answers)
    rouge_score = rouge.compute(predictions=predictions, references=answers)
    metrics = {
        "accuracy": accuracy["acc"],
        "rouge1": metric_value(rouge_score["rouge1"]),
        "rouge2": metric_value(rouge_score["rouge2"]),
        "rougeL": metric_value(rouge_score["rougeL"]),
        "rougeLsum": metric_value(rouge_score["rougeLsum"]),
    }
    metrics.update(metadata)
    return metrics


def sanitize_text(value: Any) -> str:
    return str(value).replace("\r", " ").replace("\n", " ").replace("\t", " ").strip()


def answer_text(answer: Any) -> str:
    return " | ".join(answer) if isinstance(answer, list) else str(answer)


def write_rag_output(path: str, uid: Sequence[str], questions: Sequence[str], predictions: Sequence[str], answers: Sequence[Any]):
    with open(path, "w") as f:
        for u, q, p, a in zip(uid, questions, predictions, answers):
            f.write(f"{u}\t{sanitize_text(q)}\t{sanitize_text(answer_text(a))}\t{sanitize_text(p)}\n")


def write_constraint_output(path: str, uid, questions, predictions, raw_predictions, answers):
    with open(path, "w") as f:
        for u, q, p, raw_p, a in zip(uid, questions, predictions, raw_predictions, answers):
            f.write(
                f"{u}\t{sanitize_text(q)}\t{sanitize_text(answer_text(a))}"
                f"\t{sanitize_text(p)}\t{sanitize_text(raw_p)}\n"
            )


def constraint_variant_predictions(raw_predictions: Sequence[str]) -> Dict[str, List[str]]:
    full_prediction = [extract_answer_from_json(pred) for pred in raw_predictions]
    return {
        "first_candidate": [extract_first_answer_candidate(pred) for pred in full_prediction],
        "answer_only": [strip_evidence_candidates(pred) for pred in full_prediction],
        "evidence_only": [get_evidence_candidates_text(pred) for pred in full_prediction],
        "full": full_prediction,
    }
