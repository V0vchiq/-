"""
Извлекает embeddings из существующего FAISS индекса.
Не нужно перегенерировать датасеты!
"""

import json
from pathlib import Path

try:
    import faiss
    import numpy as np
except ImportError:
    print("Установите: pip install faiss-cpu numpy")
    exit(1)

OUTPUT_DIR = Path(__file__).parent / "output"


def main():
    index_path = OUTPUT_DIR / "rag_index.faiss"
    embeddings_path = OUTPUT_DIR / "rag_embeddings.bin"
    config_path = OUTPUT_DIR / "rag_config.json"
    
    if not index_path.exists():
        print(f"FAISS индекс не найден: {index_path}")
        return
    
    print(f"Загружаем FAISS индекс: {index_path}")
    index = faiss.read_index(str(index_path))
    
    # Извлекаем векторы
    num_vectors = index.ntotal
    dim = index.d
    print(f"Найдено {num_vectors} векторов размерности {dim}")
    
    # Получаем все векторы
    embeddings = index.reconstruct_n(0, num_vectors)
    embeddings = np.array(embeddings, dtype=np.float32)
    
    # Сохраняем в бинарный файл
    embeddings.tofile(str(embeddings_path))
    print(f"Сохранено: {embeddings_path} ({embeddings_path.stat().st_size / 1024 / 1024:.1f} MB)")
    
    # Обновляем конфиг
    if config_path.exists():
        with open(config_path, "r", encoding="utf-8") as f:
            config = json.load(f)
        config["num_vectors"] = num_vectors
        with open(config_path, "w", encoding="utf-8") as f:
            json.dump(config, f, ensure_ascii=False, indent=2)
        print(f"Конфиг обновлён: {config_path}")
    
    # SHA256
    import hashlib
    with open(embeddings_path, "rb") as f:
        sha256 = hashlib.sha256(f.read()).hexdigest()
    print(f"\nSHA256 (rag_embeddings.bin): {sha256}")
    
    with open(config_path, "rb") as f:
        sha256_config = hashlib.sha256(f.read()).hexdigest()
    print(f"SHA256 (rag_config.json): {sha256_config}")
    
    print("\nЗагрузи rag_embeddings.bin и rag_config.json в Selectel")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"\nОшибка: {e}")
    input("\nНажми Enter для выхода...")
