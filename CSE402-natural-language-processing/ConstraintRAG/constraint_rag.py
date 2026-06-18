import hashlib
import json
import os
import re
from dataclasses import dataclass
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple

import torch

from model_rag import ModelRAG


DIAGNOSTIC_LABELS = {"satisfied", "missing", "contradicted", "unrelated"}
EVIDENCE_CANDIDATES_MARKER = "Evidence candidates:"


@dataclass
class ConstraintRAGConfig:
    """Configuration for the final proposed ConstraintRAG method."""

    alpha: float = 1.0
    beta: float = 0.75
    gamma: float = 0.15
    delta: float = 0.25
    final_k: int = 3
    max_constraints: int = 3
    decomposition_max_new_tokens: int = 96
    diagnostic_max_new_tokens: int = 96
    generation_batch_size: int = 8
    evidence_candidate_count: int = 10
    evidence_sentence_count: int = 2
    evidence_sentence_max_chars: int = 160
    append_evidence_candidates: bool = True
    answer_mode: str = "candidate_list"


@dataclass
class EvidenceSelection:
    passage: Any
    bm25_score: float
    diagnostic: Dict[str, str]
    score: float


def passage_to_title_text(passage: Any) -> Tuple[str, str]:
    if isinstance(passage, dict):
        title = passage.get("title") or ""
        text = passage.get("text") or passage.get("contents") or passage.get("passage") or ""
        if not title and passage.get("contents") and "\n" in str(text):
            first_line, rest = str(text).split("\n", 1)
            title = first_line.strip().strip('"')
            text = rest.strip()
        return str(title), str(text)
    return "", str(passage)


def format_passage(passage: Any) -> str:
    title, text = passage_to_title_text(passage)
    return f"Title: {title}\nPassage: {text}"


def _strip_code_fence(text: str) -> str:
    text = str(text).strip()
    if text.startswith("```"):
        text = re.sub(r"^```(?:json)?\s*", "", text, flags=re.IGNORECASE)
        text = re.sub(r"\s*```$", "", text)
    return text.strip()


def extract_json(text: str) -> Optional[Any]:
    text = _strip_code_fence(text)
    decoder = json.JSONDecoder()
    for index, char in enumerate(text):
        if char not in "[{":
            continue
        try:
            value, _ = decoder.raw_decode(text[index:])
            return value
        except json.JSONDecodeError:
            continue
    return None


def normalize_label(label: Any) -> str:
    label = str(label).strip().lower().replace(" ", "_").replace("-", "_")
    aliases = {
        "support": "satisfied",
        "supported": "satisfied",
        "satisfies": "satisfied",
        "present": "satisfied",
        "not_found": "missing",
        "absent": "missing",
        "omitted": "missing",
        "contradict": "contradicted",
        "contradiction": "contradicted",
        "conflict": "contradicted",
        "irrelevant": "unrelated",
        "not_relevant": "unrelated",
    }
    label = aliases.get(label, label)
    return label if label in DIAGNOSTIC_LABELS else "missing"


def count_diagnostic_labels(diagnostic: Dict[str, str]) -> Dict[str, int]:
    counts = {label: 0 for label in DIAGNOSTIC_LABELS}
    for label in diagnostic.values():
        counts[normalize_label(label)] += 1
    return counts


INVALID_CONSTRAINT_PATTERNS = (
    "```",
    "{",
    "}",
    "[",
    "]",
    '"constraints"',
    '"Constraints"',
    '"key"',
    '"value"',
    "JSON:",
    "Answer:",
)


def _case_get(mapping: Dict[str, Any], keys: Sequence[str]) -> Any:
    lower_to_key = {str(key).lower(): key for key in mapping.keys()}
    for key in keys:
        actual = lower_to_key.get(key.lower())
        if actual is not None:
            return mapping[actual]
    return None


def _clean_constraint_text(value: Any) -> str:
    if isinstance(value, dict):
        for left_key, right_key in (("key", "value"), ("name", "value"), ("type", "value")):
            left = _case_get(value, [left_key])
            right = _case_get(value, [right_key])
            if left is not None and right is not None:
                value = f"{left}: {right}"
                break
        else:
            for key in ("constraint", "text", "name", "description", "question", "relation", "entity", "target"):
                found = _case_get(value, [key])
                if found is not None:
                    value = found
                    break
    if isinstance(value, (list, tuple)):
        value = " ".join(str(item) for item in value if str(item).strip())

    value = str(value).strip()
    value = _strip_code_fence(value)
    value = re.sub(r"^\s*(?:[-*]|\d+[.)])\s*", "", value).strip()
    value = re.sub(r"^\s*(?:constraint|check|condition)\s*\d*\s*[:=-]\s*", "", value, flags=re.IGNORECASE).strip()
    value = re.sub(r"\s+", " ", value).strip(" \t\n\r\"'")

    lowered = value.lower()
    if not value or len(value) < 2:
        return ""
    if len(value) > 160 or len(value.split()) > 24:
        return ""
    if lowered in {"json", "constraints", "constraint", "answer", "question"}:
        return ""
    if any(pattern.lower() in lowered for pattern in INVALID_CONSTRAINT_PATTERNS):
        return ""
    if re.fullmatch(r"[\W_]+", value):
        return ""
    return value


def _unique_clean_constraints(values: Iterable[Any], max_constraints: int) -> List[str]:
    constraints = []
    seen = set()
    for value in values:
        cleaned = _clean_constraint_text(value)
        key = cleaned.lower()
        if not cleaned or key in seen:
            continue
        seen.add(key)
        constraints.append(cleaned)
        if len(constraints) >= max_constraints:
            break
    return constraints


def parse_constraints(text: str, query: Optional[str] = None, max_constraints: int = 3) -> List[str]:
    if isinstance(query, int) and max_constraints == 3:
        max_constraints = query
        query = None

    data = extract_json(text)
    candidates: List[Any] = []

    if isinstance(data, dict):
        listed = _case_get(data, ["constraints", "atomic_constraints", "items", "checks", "conditions"])
        if isinstance(listed, list):
            candidates.extend(listed)
        elif listed is not None:
            candidates.append(listed)
        else:
            for key, value in data.items():
                if isinstance(value, (str, int, float, bool)):
                    candidates.append(f"{key}: {value}")
    elif isinstance(data, list):
        candidates.extend(data)

    constraints = _unique_clean_constraints(candidates, max_constraints)
    if constraints:
        return constraints

    fallback = []
    for raw_line in str(text).splitlines():
        line = raw_line.strip()
        if not line:
            continue
        quoted = re.findall(r'"(?:constraint|text|name|description)"\s*:\s*"([^"]+)"', line, flags=re.IGNORECASE)
        if quoted:
            fallback.extend(quoted)
            continue
        line = re.sub(r"^\s*(?:[-*]|\d+[.)])\s*", "", line).strip()
        if re.match(r"^(?:constraint|check|condition)\s*\d*\s*[:=-]", line, flags=re.IGNORECASE):
            line = re.split(r"[:=-]", line, maxsplit=1)[-1].strip()
        fallback.append(line)

    constraints = _unique_clean_constraints(fallback, max_constraints)
    if constraints:
        return constraints
    return [query] if query else []


def _set_label_by_index(diagnostic: Dict[str, str], constraints: Sequence[str], index: Any, label: Any) -> None:
    try:
        numeric_index = int(index)
    except (TypeError, ValueError):
        return
    if 1 <= numeric_index <= len(constraints):
        numeric_index -= 1
    if 0 <= numeric_index < len(constraints):
        diagnostic[constraints[numeric_index]] = normalize_label(label)


def _set_label_by_constraint(diagnostic: Dict[str, str], constraint: Any, label: Any) -> None:
    constraint = str(constraint).strip()
    if constraint in diagnostic:
        diagnostic[constraint] = normalize_label(label)
        return
    lowered = constraint.lower()
    for existing in list(diagnostic.keys()):
        existing_lowered = existing.lower()
        if lowered == existing_lowered or lowered in existing_lowered or existing_lowered in lowered:
            diagnostic[existing] = normalize_label(label)
            return


def parse_diagnostics(text: str, constraints: Sequence[str]) -> Dict[str, str]:
    constraints = list(constraints)
    diagnostic = {constraint: "missing" for constraint in constraints}
    data = extract_json(text)

    if isinstance(data, dict):
        labels = _case_get(data, ["labels", "statuses", "diagnostic_labels"])
        if isinstance(labels, list):
            for constraint, label in zip(constraints, labels):
                diagnostic[constraint] = normalize_label(label)
            return diagnostic
        if isinstance(labels, dict):
            for constraint, label in labels.items():
                _set_label_by_constraint(diagnostic, constraint, label)
            return diagnostic

        diagnostics = _case_get(data, ["diagnostics", "items", "constraints"])
        if isinstance(diagnostics, list):
            for index, item in enumerate(diagnostics):
                if isinstance(item, dict):
                    label = _case_get(item, ["label", "status", "diagnosis"])
                    item_index = _case_get(item, ["index", "id", "constraint_id"])
                    item_constraint = _case_get(item, ["constraint", "text", "name"])
                    if item_index is not None:
                        _set_label_by_index(diagnostic, constraints, item_index, label)
                    elif item_constraint is not None:
                        _set_label_by_constraint(diagnostic, item_constraint, label)
                    elif label is not None:
                        _set_label_by_index(diagnostic, constraints, index, label)
                else:
                    _set_label_by_index(diagnostic, constraints, index, item)
            return diagnostic

        for index, constraint in enumerate(constraints):
            value = _case_get(data, [constraint, str(index), str(index + 1)])
            if value is not None:
                diagnostic[constraint] = normalize_label(value)
        return diagnostic

    if isinstance(data, list):
        for index, item in enumerate(data):
            if isinstance(item, dict):
                label = _case_get(item, ["label", "status", "diagnosis"])
                item_index = _case_get(item, ["index", "id", "constraint_id"])
                item_constraint = _case_get(item, ["constraint", "text", "name"])
                if item_index is not None:
                    _set_label_by_index(diagnostic, constraints, item_index, label)
                elif item_constraint is not None:
                    _set_label_by_constraint(diagnostic, item_constraint, label)
                elif label is not None:
                    _set_label_by_index(diagnostic, constraints, index, label)
            else:
                _set_label_by_index(diagnostic, constraints, index, item)
        return diagnostic

    for raw_line in str(text).splitlines():
        line = raw_line.strip().lower()
        match = re.search(r"(?:constraint\s*)?(\d+)\D+(satisfied|missing|contradicted|unrelated|supported|irrelevant|not_found)", line)
        if match:
            _set_label_by_index(diagnostic, constraints, match.group(1), match.group(2))
            continue
        for constraint in constraints:
            if constraint.lower() in line:
                label_match = re.search(r"(satisfied|missing|contradicted|unrelated|supported|irrelevant|not_found)", line)
                if label_match:
                    diagnostic[constraint] = normalize_label(label_match.group(1))
    return diagnostic


def strip_evidence_candidates(text: str) -> str:
    return str(text).split(EVIDENCE_CANDIDATES_MARKER, 1)[0].strip(" ;\t\n")


def get_evidence_candidates_text(text: str) -> str:
    text = str(text)
    if EVIDENCE_CANDIDATES_MARKER not in text:
        return ""
    return text.split(EVIDENCE_CANDIDATES_MARKER, 1)[1].strip(" ;\t\n")


def extract_first_answer_candidate(text: str) -> str:
    text = strip_evidence_candidates(text)
    text = re.sub(r"^\s*(?:[-*]|[A-Ea-e]|\d+)[.)]\s*", "", text).strip()
    text = re.split(r";|\n|\s{2,}|\s+(?:[-*]|[A-Ea-e]|\d+)[.)]\s+", text, maxsplit=1)[0]
    return text.strip(" .,:;\t\n")


def extract_answer_from_json(text: str) -> str:
    data = extract_json(text)
    if isinstance(data, dict) and "answer" in data:
        return str(data["answer"]).strip()

    match = re.search(r'"answer"\s*:\s*"([^"{}]*)', str(text))
    if match:
        return match.group(1).strip()

    text = str(text).strip()
    for marker in ("Question:", "Title:", "Passage:", "JSON:"):
        if marker in text:
            text = text.split(marker, 1)[0].strip()
    return text


QUESTION_STOPWORDS = {
    "who", "what", "when", "where", "why", "how", "is", "are", "was", "were",
    "did", "does", "do", "the", "a", "an", "of", "in", "on", "with", "to",
    "for", "from", "and", "or", "name", "called", "movie", "film", "song", "book",
    "new", "love", "me", "has", "have", "had", "get", "got", "come", "out",
}

MONTH_PATTERN = (
    "January|February|March|April|May|June|July|August|September|October|November|December|"
    "Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec"
)
DATE_PATTERN = re.compile(
    rf"\b(?:{MONTH_PATTERN})\.?\s+\d{{1,2}}(?:,)?\s+\d{{4}}\b|"
    rf"\b(?:{MONTH_PATTERN})\.?\s+\d{{4}}\b|"
    r"\b\d{1,2}(?:st|nd|rd|th)?\s+century\b|"
    r"\b(?:1[5-9]\d{2}|20\d{2})\b",
    re.IGNORECASE,
)
CAPITALIZED_PATTERN = re.compile(
    r"\b(?:[A-Z][a-zA-Z0-9&'.-]+|[A-Z]{2,})"
    r"(?:\s+(?:of|the|and|de|da|van|von|[A-Z][a-zA-Z0-9&'.-]+|[A-Z]{2,})){0,5}"
)
QUOTED_PATTERN = re.compile(r"[\"']([^\"']{2,80})[\"']")
PROPER_NOUN_PATTERN = re.compile(
    r"\b(?:[A-Z][a-zA-Z]+\.?|[A-Z]{2,})"
    r"(?:\s+(?:[A-Z][a-zA-Z]+\.?|[A-Z]{2,})){1,3}\b"
)
PROPER_WINDOW_PATTERN = re.compile(
    r"(?=\b((?:[A-Z][a-zA-Z]+\.?|[A-Z]{2,})(?:\s+(?:[A-Z][a-zA-Z]+\.?|[A-Z]{2,})){1,2})\b)"
)


def _question_terms(question: str) -> List[str]:
    words = re.findall(r"[a-z0-9]+", question.lower())
    return [word for word in words if len(word) > 2 and word not in QUESTION_STOPWORDS]


def _split_evidence_sentences(text: str) -> List[str]:
    text = re.sub(r"\s+", " ", str(text))
    return [sentence.strip() for sentence in re.split(r"(?<=[.!?])\s+", text) if len(sentence.strip()) > 12]


def _add_unique_candidate(candidates: List[str], value: Any, max_chars: int = 90) -> None:
    value = re.sub(r"\s+", " ", str(value)).strip(" .,:;\t\n")
    value = re.split(r"\.\s+(?=[A-Z])", value, maxsplit=1)[0].strip(" .,:;\t\n")
    value = re.sub(r"\s+(?:and|or)$", "", value, flags=re.IGNORECASE).strip()
    if not value or len(value) < 2 or len(value) > max_chars:
        return
    if value[0].islower() and not DATE_PATTERN.search(value):
        return
    lowered = value.lower()
    if lowered in {"question", "answer", "title", "passage", "wikipedia", "references", "external links"}:
        return
    words = value.split()
    if len(words) <= 3 and words[0].lower().strip(".'") in {"it", "the", "a", "an", "he", "she", "why", "after", "by", "in"}:
        return
    if len(words) <= 3 and words[-1].lower().strip(".'") in {"the", "a", "an", "and", "or"}:
        return
    key = re.sub(r"[^a-z0-9]+", " ", lowered).strip()
    if not key:
        return
    existing = {re.sub(r"[^a-z0-9]+", " ", candidate.lower()).strip() for candidate in candidates}
    if key in existing:
        return
    candidates.append(value)


def _score_evidence_sentences(question: str, passages: Sequence[Any]) -> List[Tuple[float, str]]:
    terms = _question_terms(question)
    scored = []
    for rank, passage in enumerate(passages):
        title, text = passage_to_title_text(passage)
        for position, sentence in enumerate(_split_evidence_sentences(text)[:8]):
            lexical = sum(1 for term in terms if term in sentence.lower())
            title_bonus = 0.25 if any(term in title.lower() for term in terms) else 0.0
            score = lexical + title_bonus - 0.08 * rank - 0.01 * position
            scored.append((score, sentence))
    return sorted(scored, key=lambda item: item[0], reverse=True)


def _candidate_priority(question_lower: str, candidate: str) -> Tuple[int, int, int]:
    normalized = candidate.strip()
    words = normalized.split()
    lower = normalized.lower()
    if question_lower.startswith("when"):
        return (0 if DATE_PATTERN.search(normalized) else 3, -len(words), len(normalized))
    if question_lower.startswith("who"):
        if 2 <= len(words) <= 3:
            return (0, len(normalized), 0)
        if 4 <= len(words) <= 5:
            return (1, len(normalized), 0)
        if len(words) == 1:
            return (2, len(normalized), 0)
        return (3, len(normalized), 0)
    if question_lower.startswith("where"):
        place_hint = any(
            hint in lower
            for hint in ("river", "city", "state", "country", "ocean", "sea", "lake", "seaway", "island", "mount", "valley")
        )
        return (0 if place_hint else 1, -len(words), len(normalized))
    return (0 if len(words) >= 2 else 1, -len(words), len(normalized))


def _add_capitalized_variants(candidates: List[str], value: str, max_chars: int = 90) -> None:
    if " and " in value:
        parts = [part.strip() for part in value.split(" and ")]
        for part in parts:
            if re.search(r"[A-Z]", part):
                _add_unique_candidate(candidates, part, max_chars=max_chars)
                if part.startswith("St. "):
                    _add_unique_candidate(candidates, "Saint " + part[4:], max_chars=max_chars)
    _add_unique_candidate(candidates, value, max_chars=max_chars)
    if value.startswith("St. "):
        _add_unique_candidate(candidates, "Saint " + value[4:], max_chars=max_chars)


def extract_evidence_candidates(
    question: str,
    passages: Sequence[Any],
    max_candidates: int = 10,
    sentence_count: int = 2,
    sentence_max_chars: int = 160,
) -> List[str]:
    candidates: List[str] = []
    question_lower = question.lower()
    scored_sentences = _score_evidence_sentences(question, passages)
    sentence_pool = " ".join(sentence for _, sentence in scored_sentences[:8])

    title_and_text_chunks = []
    for passage in passages:
        title, text = passage_to_title_text(passage)
        title_and_text_chunks.append(f"{title} {str(text)[:1000]}")
    broad_pool = " ".join(title_and_text_chunks)
    combined_pool = f"{sentence_pool} {broad_pool}"
    candidate_slots = max(1, max_candidates - max(sentence_count, 0))

    if question_lower.startswith("when") or " date " in f" {question_lower} " or " year " in f" {question_lower} ":
        for match in DATE_PATTERN.finditer(combined_pool):
            _add_unique_candidate(candidates, match.group(0))
            if len(candidates) >= candidate_slots:
                break

    raw_candidates: List[str] = []
    for match in PROPER_WINDOW_PATTERN.finditer(combined_pool):
        raw_candidates.append(match.group(1))
    for match in PROPER_NOUN_PATTERN.finditer(combined_pool):
        raw_candidates.append(match.group(0))
    for match in QUOTED_PATTERN.finditer(combined_pool):
        raw_candidates.append(match.group(1))
    for match in CAPITALIZED_PATTERN.finditer(combined_pool):
        candidate = match.group(0)
        if len(candidate.split()) <= 7:
            raw_candidates.append(candidate)
            if " and " in candidate:
                raw_candidates.extend(part.strip() for part in candidate.split(" and ") if re.search(r"[A-Z]", part))

    raw_candidates = sorted(raw_candidates, key=lambda candidate: _candidate_priority(question_lower, candidate))
    for candidate in raw_candidates:
        if len(candidates) >= candidate_slots:
            break
        _add_capitalized_variants(candidates, candidate)

    for passage in passages:
        if len(candidates) >= candidate_slots:
            break
        title, _ = passage_to_title_text(passage)
        _add_unique_candidate(candidates, title)

    added_sentences = 0
    for _, sentence in scored_sentences:
        if added_sentences >= sentence_count or len(candidates) >= max_candidates:
            break
        before = len(candidates)
        _add_unique_candidate(candidates, sentence[:sentence_max_chars], max_chars=sentence_max_chars)
        if len(candidates) > before:
            added_sentences += 1
    return candidates[:max_candidates]


def _looks_like_bad_generation(text: str) -> bool:
    stripped = text.strip()
    if not stripped:
        return True
    lowered = stripped.lower()
    if any(marker.lower() in lowered for marker in ("Question:", "Passage:", "Title:", "Answer the question")):
        return True
    return len(stripped.split()) > 18


class ConstraintRAG(ModelRAG):
    """Final proposed constraint-guided RAG method."""

    def __init__(self, config: Optional[ConstraintRAGConfig] = None, cache_path: Optional[str] = None):
        super().__init__()
        self.config = config or ConstraintRAGConfig()
        self.cache_path = cache_path
        self.cache: Dict[str, Any] = {}
        self._last_evidence_candidates: List[List[str]] = []
        if cache_path and os.path.exists(cache_path):
            with open(cache_path, "r") as f:
                for line in f:
                    record = json.loads(line)
                    self.cache[record["key"]] = record["value"]

    def _cache_key(self, kind: str, *parts: str) -> str:
        payload = json.dumps([kind, *parts], sort_keys=True, ensure_ascii=False)
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

    def build_decomposition_prompt(self, query: str) -> str:
        return (
            "Break the question into at most three atomic evidence checks for passage selection.\n"
            "Rules:\n"
            "- Write one short check per line.\n"
            "- Do not use JSON, markdown, brackets, or explanations.\n"
            "- Include answer type, entity/relation, and time/location qualifier only when present.\n"
            "Examples:\n"
            "Question: who played dwight's sister on the office\n"
            "1. actor who played Dwight's sister\n"
            "2. television show The Office\n"
            "Question: when did bat out of hell get released\n"
            "1. release date of Bat Out of Hell\n"
            f"Question: {query}\n"
            "Checks:\n"
        )

    def build_diagnostic_prompt(self, query: str, constraints: Sequence[str], passage: Any) -> str:
        numbered = "\n".join(f"{index + 1}. {constraint}" for index, constraint in enumerate(constraints))
        return (
            "For each numbered check, decide whether the passage gives evidence for the check.\n"
            "Use exactly these labels:\n"
            "satisfied = the passage directly supports the check;\n"
            "missing = the passage does not contain enough evidence;\n"
            "contradicted = the passage conflicts with the check;\n"
            "unrelated = the passage is about a different topic.\n"
            "Return JSON only as {\"labels\": [label_for_1, label_for_2, ...]}.\n"
            f"Question: {query}\n"
            f"Checks:\n{numbered}\n"
            f"{format_passage(passage)}\n"
            "JSON:"
        )

    def build_answer_prompt(self, query: str, selections: Sequence[EvidenceSelection]) -> str:
        context = "\n".join(format_passage(selection.passage) for selection in selections)
        if self.config.answer_mode == "short_answer":
            return (
                "Answer the question using only the passages. "
                "Write only the short answer, with no explanation. "
                "If multiple answers seem possible, choose the one most directly supported by the passages.\n"
                f"{context}\n"
                f"Question: {query}\n"
                "Answer:"
            )
        return (
            "Answer the question using only the passages. "
            "Write a compact answer candidate list, starting with the best answer. "
            "Use semicolons only if there are aliases or equally plausible candidates.\n"
            f"{context}\n"
            f"Question: {query}\n"
            "Answer candidates:"
        )

    def decompose_question(self, query: str) -> List[str]:
        return self.decompose_questions([query])[0]

    def decompose_questions(self, queries: Sequence[str]) -> List[List[str]]:
        results: List[Optional[List[str]]] = [None] * len(queries)
        uncached_indices = []
        prompts = []
        for index, query in enumerate(queries):
            key = self._cache_key("constraints", query)
            if key in self.cache:
                results[index] = list(self.cache[key])
            else:
                uncached_indices.append(index)
                prompts.append(self.build_decomposition_prompt(query))

        texts = self._generate_texts(prompts, max_new_tokens=self.config.decomposition_max_new_tokens)
        for index, text in zip(uncached_indices, texts):
            query = queries[index]
            constraints = parse_constraints(text, query=query, max_constraints=self.config.max_constraints)
            self._set_cache(self._cache_key("constraints", query), constraints)
            results[index] = constraints
        return [list(result or [query]) for result, query in zip(results, queries)]

    def diagnose_passage(self, query: str, constraints: Sequence[str], passage: Any) -> Dict[str, str]:
        return self.diagnose_passages(query, constraints, [passage])[0]

    def diagnose_passages(self, query: str, constraints: Sequence[str], passages: Sequence[Any]) -> List[Dict[str, str]]:
        constraints = list(constraints)
        results: List[Optional[Dict[str, str]]] = [None] * len(passages)
        uncached_indices = []
        prompts = []
        constraints_json = json.dumps(constraints, ensure_ascii=False)
        for index, passage in enumerate(passages):
            _, passage_text = passage_to_title_text(passage)
            key = self._cache_key("diagnostic", query, constraints_json, passage_text)
            if key in self.cache:
                results[index] = dict(self.cache[key])
            else:
                uncached_indices.append(index)
                prompts.append(self.build_diagnostic_prompt(query, constraints, passage))

        texts = self._generate_texts(prompts, max_new_tokens=self.config.diagnostic_max_new_tokens)
        for index, text in zip(uncached_indices, texts):
            passage = passages[index]
            _, passage_text = passage_to_title_text(passage)
            diagnostic = parse_diagnostics(text, constraints)
            self._set_cache(self._cache_key("diagnostic", query, constraints_json, passage_text), diagnostic)
            results[index] = diagnostic
        return [dict(result or parse_diagnostics("", constraints)) for result in results]

    def _diagnostic_score(self, diagnostic: Dict[str, str]) -> float:
        counts = count_diagnostic_labels(diagnostic)
        return (
            self.config.beta * counts["satisfied"]
            - self.config.gamma * counts["missing"]
            - self.config.delta * counts["contradicted"]
        )

    def _select_passages(
        self,
        passages: Sequence[Any],
        scores: Sequence[float],
        diagnostics: Sequence[Dict[str, str]],
    ) -> List[EvidenceSelection]:
        selections = [
            EvidenceSelection(
                passage=passage,
                bm25_score=float(score),
                diagnostic=diagnostic,
                score=self.config.alpha * float(score) + self._diagnostic_score(diagnostic),
            )
            for passage, score, diagnostic in zip(passages, scores, diagnostics)
        ]
        if not selections:
            return []

        selected: List[EvidenceSelection] = [selections[0]]
        seen = {id(selections[0].passage)}

        diagnostic_ranked = sorted(
            selections[1:],
            key=lambda item: (self._diagnostic_score(item.diagnostic), item.bm25_score),
            reverse=True,
        )
        for item in diagnostic_ranked:
            if len(selected) >= self.config.final_k:
                break
            counts = count_diagnostic_labels(item.diagnostic)
            if counts["satisfied"] <= 0 or id(item.passage) in seen:
                continue
            selected.append(item)
            seen.add(id(item.passage))

        for item in selections:
            if len(selected) >= self.config.final_k:
                break
            if id(item.passage) in seen:
                continue
            selected.append(item)
            seen.add(id(item.passage))
        return selected[: self.config.final_k]

    def make_augmented_inputs_for_generate(self, queries, qids, k=5):
        list_passages, list_scores = self.search(queries, qids, k=k)
        list_constraints = self.decompose_questions(list(queries))
        prompts = []
        evidence_candidates = []
        for query, passages, scores, constraints in zip(queries, list_passages, list_scores, list_constraints):
            diagnostics = self.diagnose_passages(query, constraints, passages)
            selected = self._select_passages(passages, scores, diagnostics)
            prompts.append(self.build_answer_prompt(query, selected))
            evidence_candidates.append(
                extract_evidence_candidates(
                    query,
                    passages,
                    max_candidates=self.config.evidence_candidate_count,
                    sentence_count=self.config.evidence_sentence_count,
                    sentence_max_chars=self.config.evidence_sentence_max_chars,
                )
            )
        self._last_evidence_candidates = evidence_candidates
        return prompts

    @torch.no_grad()
    def retrieval_augmented_generate(self, queries, qids, k=5, **kwargs):
        prompts = self.make_augmented_inputs_for_generate(queries, qids, k=k)
        device = self._model_device()
        inputs = self.tokenizer(prompts, return_tensors="pt", padding=True, truncation=True)
        inputs = {key: value.to(device) for key, value in inputs.items()}
        outputs = self.model.generate(**inputs, **kwargs)
        new_tokens = outputs[:, inputs["input_ids"].shape[1]:]
        generated = self.tokenizer.batch_decode(new_tokens, skip_special_tokens=True, clean_up_tokenization_spaces=False)

        final_texts = []
        for text, candidates in zip(generated, self._last_evidence_candidates):
            text = extract_answer_from_json(text)
            pieces = [text.strip()] if text.strip() else []
            should_append = self.config.append_evidence_candidates
            if self.config.answer_mode != "short_answer":
                should_append = should_append or _looks_like_bad_generation(text)
            if should_append and candidates:
                pieces.append(EVIDENCE_CANDIDATES_MARKER + " " + "; ".join(candidates))
            final_texts.append("; ".join(piece for piece in pieces if piece).strip())

        encoded = self.tokenizer(final_texts, return_tensors="pt", padding=True, add_special_tokens=False)
        return encoded["input_ids"].to(device)


__all__ = [
    "ConstraintRAGConfig",
    "ConstraintRAG",
    "EVIDENCE_CANDIDATES_MARKER",
    "extract_answer_from_json",
    "extract_evidence_candidates",
    "extract_first_answer_candidate",
    "extract_json",
    "format_passage",
    "get_evidence_candidates_text",
    "parse_constraints",
    "parse_diagnostics",
    "passage_to_title_text",
    "strip_evidence_candidates",
]
