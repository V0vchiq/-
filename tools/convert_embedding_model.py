"""
Конвертация embedding модели в ONNX для мобильного RAG.

Запуск:
    python convert_embedding_model.py

Результат:
    - output/embedding_model.onnx
"""

import os
from pathlib import Path

# Check dependencies
try:
    import torch
    from transformers import AutoTokenizer, AutoModel
except ImportError:
    print("Установите: pip install torch transformers")
    exit(1)

MODEL_NAME = "intfloat/multilingual-e5-small"
OUTPUT_DIR = Path(__file__).parent / "output"


def main():
    print(f"Загружаем модель {MODEL_NAME}...")
    tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)
    model = AutoModel.from_pretrained(MODEL_NAME)
    model.eval()
    
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    
    # Пример входных данных для трассировки
    dummy_text = "query: тестовый запрос"
    inputs = tokenizer(
        dummy_text,
        padding=True,
        truncation=True,
        max_length=512,
        return_tensors="pt"
    )
    
    output_path = OUTPUT_DIR / "embedding_model.onnx"
    
    print(f"Конвертируем в ONNX...")
    
    # Экспорт в ONNX
    torch.onnx.export(
        model,
        (inputs["input_ids"], inputs["attention_mask"]),
        str(output_path),
        input_names=["input_ids", "attention_mask"],
        output_names=["last_hidden_state"],
        dynamic_axes={
            "input_ids": {0: "batch_size", 1: "sequence"},
            "attention_mask": {0: "batch_size", 1: "sequence"},
            "last_hidden_state": {0: "batch_size", 1: "sequence"},
        },
        opset_version=14,
        do_constant_folding=True,
    )
    
    # Сохраняем токенизатор
    tokenizer_path = OUTPUT_DIR / "embedding_tokenizer"
    tokenizer.save_pretrained(str(tokenizer_path))
    
    print(f"\nГотово!")
    print(f"Модель: {output_path} ({output_path.stat().st_size / 1024 / 1024:.1f} MB)")
    print(f"Токенизатор: {tokenizer_path}")
    
    # SHA256
    import hashlib
    with open(output_path, "rb") as f:
        sha256 = hashlib.sha256(f.read()).hexdigest()
    print(f"SHA256: {sha256}")
    
    print("\nЗагрузи embedding_model.onnx в Selectel и скинь ссылку + хеш")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"\nОшибка: {e}")
    input("\nНажми Enter для выхода...")
