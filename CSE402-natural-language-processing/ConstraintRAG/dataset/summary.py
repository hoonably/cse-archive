import os
import shutil
import datasets
import itertools
import functools
import torch


def prepare_summary_dataset(tokenizer,
                             dataset_name_or_path: str = "abisee/cnn_dailymail",
                             dataset_subset: str = "3.0.0",
                             context_max_length: int = 896,
                             target_max_length: int = 128,
                             context_column_name: str = "article",
                             target_column_name: str = "highlights",
                             prompt: str = "Context: {context}\n Summary:\n",
                             train_sample_size: int =-1,
                             cache_path:str="cache"):
    summary_cache_path = os.path.join(cache_path, "summary") if cache_path is not None else None
    if summary_cache_path is not None and os.path.exists(summary_cache_path):
        try:
            print(f"Using pre-downloaded dataset from {cache_path}.")
            train = datasets.load_from_disk(os.path.join(summary_cache_path, "train"))
            validation = datasets.load_from_disk(os.path.join(summary_cache_path, "eval"))
            return train, validation
        except (FileNotFoundError, OSError, ValueError) as exc:
            print(f"Summary cache at {summary_cache_path} is invalid; rebuilding it. ({exc})")
            shutil.rmtree(summary_cache_path, ignore_errors=True)

    print(f"Download and prerpocessing dataset from {dataset_name_or_path} on subset {dataset_subset}...")
    dataset = datasets.load_dataset(dataset_name_or_path, dataset_subset)
    if "eval" in dataset:
        validation_split = "eval"
    elif "test" in dataset:
        validation_split = "test"
    else:
        print("Using train split for validation.")
        dataset = datasets.train_test_split(test_size=0.1)
        validation_split = "test"

    train = dataset["train"] if train_sample_size == -1 else dataset["train"].select(range(train_sample_size))
    validation = dataset[validation_split]

    processing_lambda = functools.partial(
        _preprocess,
        tokenizer=tokenizer,
        context_column_name=context_column_name,
        target_column_name=target_column_name,
        context_max_length=context_max_length,
        target_max_length=target_max_length,
        prompt=prompt
    )
    train = train.map(
        processing_lambda,
        batched=True,
        remove_columns=train.column_names,
        num_proc=1,
        batch_size=64,
        desc="Preprocessing",
    )
    validation = validation.map(
        processing_lambda,
        batched=True,
        remove_columns=validation.column_names,
        num_proc=1,
        batch_size=64,
        desc="Preprocessing",
    )

    if cache_path is not None:
        os.makedirs(os.path.join(cache_path,"summary"), exist_ok=True)
        print(f"Saving dataset to {cache_path}...")
        train.save_to_disk(os.path.join(cache_path,"summary","train"), max_shard_size="500MB")
        validation.save_to_disk(os.path.join(cache_path,"summary","eval"), max_shard_size="500MB")
    return train, validation

def _preprocess(examples, tokenizer, context_column_name, target_column_name, context_max_length, target_max_length, prompt):
    contexts = tokenizer(examples[context_column_name], add_special_tokens=False, truncation=True, max_length=context_max_length-10)
    targets = tokenizer(examples[target_column_name], add_special_tokens=False, truncation=True, max_length=target_max_length)
    contexts = tokenizer.batch_decode(contexts["input_ids"], skip_special_tokens=True)
    targets = tokenizer.batch_decode(targets["input_ids"], skip_special_tokens=True)

    # fill here
    ######

    #### YOUR CODES; TODO
    input_ids_list = []
    attention_mask_list = []
    labels_list = []
    total_max_length = context_max_length + target_max_length
    pad_token_id = tokenizer.pad_token_id
    if pad_token_id is None:
        pad_token_id = tokenizer.eos_token_id

    for context, target in zip(contexts, targets):
        prompt_text = prompt.format(context=context)
        target_text = target
        if tokenizer.eos_token is not None:
            target_text = f"{target_text}{tokenizer.eos_token}"

        prompt_ids = tokenizer(
            prompt_text,
            add_special_tokens=False,
            padding=False,
        )["input_ids"]
        target_ids = tokenizer(
            target_text,
            add_special_tokens=False,
            truncation=True,
            max_length=target_max_length,
            padding=False,
        )["input_ids"]

        available_prompt_length = max(total_max_length - len(target_ids), 0)
        if len(prompt_ids) > available_prompt_length:
            prompt_ids = prompt_ids[-available_prompt_length:] if available_prompt_length > 0 else []
        if len(target_ids) > total_max_length:
            target_ids = target_ids[:total_max_length]

        input_ids = prompt_ids + target_ids
        attention_mask = [1] * len(input_ids)
        labels = [-100] * len(prompt_ids) + target_ids.copy()

        pad_length = total_max_length - len(input_ids)
        if pad_length > 0:
            pad_ids = [pad_token_id] * pad_length
            pad_attention = [0] * pad_length
            pad_labels = [-100] * pad_length
            if tokenizer.padding_side == "left":
                input_ids = pad_ids + input_ids
                attention_mask = pad_attention + attention_mask
                labels = pad_labels + labels
            else:
                input_ids = input_ids + pad_ids
                attention_mask = attention_mask + pad_attention
                labels = labels + pad_labels

        input_ids_list.append(input_ids)
        attention_mask_list.append(attention_mask)
        labels_list.append(labels)

    inputs = {
        "input_ids": input_ids_list,
        "attention_mask": attention_mask_list,
        "labels": labels_list,
    }

    ######
    return inputs

def collate_fn_for_summary(batch, tokenizer, pad_to_multiple_of=1024):
    input_ids = [example["input_ids"] for example in batch]
    attention_mask = [example["attention_mask"] for example in batch]
    labels = [example["labels"] for example in batch]

    input_ids = torch.tensor(input_ids, dtype=torch.long)
    attention_mask = torch.tensor(attention_mask, dtype=torch.long)
    labels = torch.tensor(labels, dtype=torch.long)

    max_seq_length = attention_mask.eq(1).sum(-1).max().item()
    if max_seq_length % pad_to_multiple_of != 0:
        max_seq_length = (max_seq_length // pad_to_multiple_of + 1) * pad_to_multiple_of

    if tokenizer.padding_side == "left":
        input_ids = input_ids[:, -max_seq_length:]
        attention_mask = attention_mask[:, -max_seq_length:]
        labels = labels[:, -max_seq_length:]
    else:
        input_ids = input_ids[:, :max_seq_length]
        attention_mask = attention_mask[:, :max_seq_length]
        labels = labels[:, :max_seq_length]

    return {
        "input_ids": input_ids,
        "attention_mask": attention_mask,
        "labels": labels
    }
