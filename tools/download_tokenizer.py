"""
Скачивает SentencePiece модель для embedding токенизации.
"""

from pathlib import Path
from huggingface_hub import hf_hub_download

OUTPUT_DIR = Path(__file__).parent / "output"

def main():
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    
    print("Скачиваем sentencepiece.bpe.model...")
    
    # Для multilingual-e5-small
    path = hf_hub_download(
        repo_id="intfloat/multilingual-e5-small",
        filename="sentencepiece.bpe.model",
        local_dir=OUTPUT_DIR,
    )
    
    print(f"Скачано: {path}")
    
    # SHA256
    import hashlib
    with open(path, "rb") as f:
        sha256 = hashlib.sha256(f.read()).hexdigest()
    print(f"SHA256: {sha256}")
    
    file_size = Path(path).stat().st_size / 1024
    print(f"Размер: {file_size:.1f} KB")
    
    print("\nЗагрузи sentencepiece.bpe.model в Selectel")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"Ошибка: {e}")
    input("\nНажми Enter для выхода...")
