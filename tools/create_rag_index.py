"""
RAG Index Creator for Nexus
===========================
Создаёт базу знаний и FAISS индекс для офлайн RAG.

Требования:
    pip install torch sentence-transformers faiss-cpu datasets tqdm

Запуск:
    python create_rag_index.py

Результат:
    - rag_base.db (SQLite база с текстами)
    - rag_index.faiss (FAISS индекс)
    - rag_config.json (метаданные)
"""

import json
import sqlite3
import os
import sys
from pathlib import Path
from tqdm import tqdm

# Check dependencies
try:
    import torch
    from sentence_transformers import SentenceTransformer
    import faiss
    import numpy as np
    from datasets import load_dataset
except ImportError as e:
    print("Установите зависимости:")
    print("pip install torch sentence-transformers faiss-cpu datasets tqdm numpy")
    sys.exit(1)


# === CONFIGURATION ===
EMBEDDING_MODEL = "intfloat/multilingual-e5-small"  # 384 dim, хорош для русского
EMBEDDING_DIM = 384
BATCH_SIZE = 128  # Для GPU
MAX_TEXT_LENGTH = 512  # Максимум символов на chunk
OUTPUT_DIR = Path(__file__).parent / "output"

# Датасеты для загрузки
DATASETS_CONFIG = [
    {
        "name": "wikipedia_ru",
        "hf_path": "wikimedia/wikipedia",
        "hf_config": "20231101.ru",
        "split": "train",
        "text_field": "text",
        "title_field": "title",
        "max_samples": 100000,
        "min_length": 500,
        "filter_important": True,
        "streaming": True,
    },
    {
        "name": "sberquad",
        "hf_path": "sberquad",
        "split": "train",
        "text_field": "context",
        "max_samples": 25000,
    },
    {
        "name": "ru_alpaca",
        "hf_path": "IlyaGusev/ru_turbo_alpaca",
        "split": "train",
        "text_field": "output",
        "max_samples": 15000,
    },
]

# Важные категории для фильтрации Wikipedia
IMPORTANT_KEYWORDS = [
    # Люди
    "родился", "родилась", "писатель", "поэт", "учёный", "физик", "химик", "математик",
    "художник", "композитор", "музыкант", "актёр", "актриса", "режиссёр", "политик",
    "президент", "император", "царь", "король", "полководец", "космонавт", "изобретатель",
    # История  
    "война", "битва", "революция", "восстание", "империя", "государство", "династия",
    "договор", "конституция", "независимость",
    # Наука
    "теория", "закон", "открытие", "элемент", "планета", "звезда", "галактика",
    "атом", "молекула", "клетка", "ген", "эволюция", "гравитация",
    # География
    "страна", "столица", "город", "река", "озеро", "гора", "океан", "море", "остров",
    "континент", "население", "площадь",
    # Культура
    "роман", "фильм", "опера", "балет", "симфония", "картина", "скульптура",
    "премия", "олимпийские", "чемпионат",
]


def setup_device():
    """Определяем устройство (GPU/CPU)"""
    if torch.cuda.is_available():
        device = "cuda"
        gpu_name = torch.cuda.get_device_name(0)
        vram = torch.cuda.get_device_properties(0).total_memory / 1024**3
        print(f"GPU: {gpu_name} ({vram:.1f} GB)")
    else:
        device = "cpu"
        print("GPU не найден, используем CPU (будет медленно)")
    return device


def create_database(db_path: Path):
    """Создаём SQLite базу"""
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS documents (
            id INTEGER PRIMARY KEY,
            text TEXT NOT NULL,
            source TEXT,
            metadata TEXT
        )
    """)
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_source ON documents(source)")
    conn.commit()
    return conn


def chunk_text(text: str, max_length: int = MAX_TEXT_LENGTH) -> list[str]:
    """Разбиваем длинный текст на chunks"""
    text = text.strip()
    if len(text) <= max_length:
        return [text] if text else []
    
    chunks = []
    sentences = text.replace("。", ".").replace("！", "!").replace("？", "?").split(".")
    
    current_chunk = ""
    for sentence in sentences:
        sentence = sentence.strip()
        if not sentence:
            continue
        
        if len(current_chunk) + len(sentence) + 1 <= max_length:
            current_chunk += sentence + ". "
        else:
            if current_chunk:
                chunks.append(current_chunk.strip())
            current_chunk = sentence + ". "
    
    if current_chunk:
        chunks.append(current_chunk.strip())
    
    return chunks


def load_and_process_datasets(conn: sqlite3.Connection) -> int:
    """Загружаем датасеты и сохраняем в базу"""
    cursor = conn.cursor()
    total_docs = 0
    seen_texts = set()
    
    for config in DATASETS_CONFIG:
        print(f"\nЗагружаем {config['name']}...")
        try:
            hf_config = config.get("hf_config")
            use_streaming = config.get("streaming", False)
            
            if hf_config:
                dataset = load_dataset(
                    config["hf_path"],
                    hf_config,
                    split=config["split"],
                    streaming=use_streaming,
                )
            else:
                dataset = load_dataset(
                    config["hf_path"], 
                    split=config["split"],
                    streaming=use_streaming,
                )
        except Exception as e:
            print(f"  Ошибка загрузки {config['name']}: {e}")
            continue
        
        count = 0
        skipped = 0
        min_length = config.get("min_length", 20)
        filter_important = config.get("filter_important", False)
        title_field = config.get("title_field")
        
        for item in tqdm(dataset, desc=f"  Обработка {config['name']}"):
            if count >= config["max_samples"]:
                break
            
            text = item.get(config["text_field"], "")
            if not text or len(text) < min_length:
                skipped += 1
                continue
            
            # Фильтр по важности для Wikipedia
            if filter_important:
                text_lower = text[:2000].lower()  # Проверяем начало статьи
                title = item.get(title_field, "") if title_field else ""
                title_lower = title.lower()
                
                is_important = any(kw in text_lower or kw in title_lower for kw in IMPORTANT_KEYWORDS)
                # Также берём длинные статьи (>2000 символов) - они обычно важные
                is_important = is_important or len(text) > 2000
                
                if not is_important:
                    skipped += 1
                    continue
            
            # Для Wikipedia добавляем заголовок
            if title_field and item.get(title_field):
                title = item.get(title_field)
                text = f"{title}. {text}"
            
            chunks = chunk_text(text)
            for chunk in chunks:
                # Дедупликация
                text_hash = hash(chunk[:100])
                if text_hash in seen_texts:
                    continue
                seen_texts.add(text_hash)
                
                cursor.execute(
                    "INSERT INTO documents (text, source) VALUES (?, ?)",
                    (chunk, config["name"])
                )
                total_docs += 1
                count += 1
        
        print(f"  Добавлено: {count} документов (пропущено: {skipped})")
    
    conn.commit()
    return total_docs


def add_faq_data(conn: sqlite3.Connection) -> int:
    """Добавляем базовые FAQ"""
    faq_items = [
        # === ИЗВЕСТНЫЕ ЛЮДИ ===
        "Александр Сергеевич Пушкин (1799-1837) — великий русский поэт, родился 6 июня 1799 года в Москве. Основоположник современного русского литературного языка. Автор «Евгения Онегина», «Капитанской дочки», «Бориса Годунова», сказок и множества стихотворений.",
        "Лев Николаевич Толстой (1828-1910) — русский писатель, родился 9 сентября 1828 года в Ясной Поляне. Автор романов «Война и мир», «Анна Каренина», «Воскресение». Один из величайших писателей мировой литературы.",
        "Фёдор Михайлович Достоевский (1821-1881) — русский писатель, родился 11 ноября 1821 года в Москве. Автор романов «Преступление и наказание», «Идиот», «Братья Карамазовы», «Бесы».",
        "Михаил Юрьевич Лермонтов (1814-1841) — русский поэт и писатель, родился 15 октября 1814 года в Москве. Автор романа «Герой нашего времени», поэм «Мцыри», «Демон».",
        "Николай Васильевич Гоголь (1809-1852) — русский писатель, родился 1 апреля 1809 года. Автор «Мёртвых душ», «Ревизора», «Вечеров на хуторе близ Диканьки», повести «Шинель».",
        "Антон Павлович Чехов (1860-1904) — русский писатель и драматург, родился 29 января 1860 года в Таганроге. Автор пьес «Чайка», «Вишнёвый сад», «Три сестры», множества рассказов.",
        "Пётр Ильич Чайковский (1840-1893) — великий русский композитор. Автор балетов «Лебединое озеро», «Щелкунчик», «Спящая красавица», опер «Евгений Онегин», «Пиковая дама».",
        "Альберт Эйнштейн (1879-1955) — физик-теоретик, создатель теории относительности. Лауреат Нобелевской премии по физике 1921 года. Родился в Германии.",
        "Исаак Ньютон (1643-1727) — английский физик и математик. Открыл закон всемирного тяготения, три закона механики, разработал дифференциальное исчисление.",
        "Леонардо да Винчи (1452-1519) — итальянский художник, учёный, изобретатель эпохи Возрождения. Автор картин «Мона Лиза», «Тайная вечеря».",
        "Наполеон Бонапарт (1769-1821) — французский император и полководец. Провёл множество войн в Европе, потерпел поражение в России в 1812 году.",
        "Юрий Алексеевич Гагарин (1934-1968) — советский космонавт, первый человек в космосе. 12 апреля 1961 года совершил полёт на корабле «Восток-1» продолжительностью 108 минут.",
        "Нил Армстронг (1930-2012) — американский астронавт, первый человек на Луне. 20 июля 1969 года ступил на поверхность Луны в рамках миссии «Аполлон-11».",
        "Владимир Ильич Ленин (1870-1924) — революционер, основатель Советского государства. Возглавил Октябрьскую революцию 1917 года.",
        "Иосиф Виссарионович Сталин (1878-1953) — советский государственный деятель, руководитель СССР с 1924 по 1953 год. Возглавлял страну во время Великой Отечественной войны.",
        
        # === ИСТОРИЯ ===
        "Великая Отечественная война (1941-1945) — война СССР против нацистской Германии. Началась 22 июня 1941 года, закончилась 9 мая 1945 года победой СССР. Погибло около 27 миллионов советских граждан.",
        "Вторая мировая война (1939-1945) — крупнейший вооружённый конфликт в истории человечества. Участвовало 62 государства. Погибло более 70 миллионов человек.",
        "Первая мировая война (1914-1918) — война между двумя коалициями: Антантой и Центральными державами. Погибло около 17 миллионов человек.",
        "Октябрьская революция произошла 7 ноября (25 октября по старому стилю) 1917 года в России. Привела к свержению Временного правительства и установлению советской власти.",
        "Отечественная война 1812 года — война России против наполеоновской Франции. Закончилась победой России и изгнанием французов. Бородинская битва состоялась 7 сентября 1812 года.",
        "СССР (Союз Советских Социалистических Республик) существовал с 1922 по 1991 год. Включал 15 союзных республик. Распался 26 декабря 1991 года.",
        "Крещение Руси произошло в 988 году при князе Владимире Святославиче. Русь приняла христианство по византийскому образцу.",
        "Куликовская битва состоялась 8 сентября 1380 года. Русские войска под командованием Дмитрия Донского одержали победу над Мамаем.",
        "Пётр I Великий (1672-1725) — русский царь и первый российский император. Провёл масштабные реформы, основал Санкт-Петербург в 1703 году.",
        "Екатерина II Великая (1729-1796) — российская императрица с 1762 года. При ней Россия значительно расширила территорию, присоединив Крым и часть Польши.",
        
        # === КОСМОС И НАУКА ===
        "Солнце — звезда в центре Солнечной системы. Диаметр около 1,4 миллиона километров. Температура поверхности около 5500°C, ядра — около 15 миллионов градусов.",
        "Земля — третья планета от Солнца, единственная известная планета с жизнью. Возраст около 4,5 миллиарда лет. Диаметр 12 742 км.",
        "Луна — единственный естественный спутник Земли. Расстояние до Земли около 384 400 км. Диаметр 3 474 км.",
        "Марс — четвёртая планета от Солнца, красная планета. Имеет два спутника: Фобос и Деймос. Диаметр 6 779 км.",
        "Юпитер — крупнейшая планета Солнечной системы. Газовый гигант с Большим красным пятном — гигантским штормом. Имеет 95 известных спутников.",
        "Скорость света в вакууме составляет примерно 299 792 458 метров в секунду (около 300 000 км/с). Это максимальная скорость во Вселенной.",
        "Чёрная дыра — область пространства с настолько сильной гравитацией, что даже свет не может её покинуть. Образуется при коллапсе массивных звёзд.",
        "Галактика Млечный Путь содержит от 100 до 400 миллиардов звёзд. Диаметр около 100 000 световых лет. Солнечная система находится в рукаве Ориона.",
        "МКС (Международная космическая станция) — пилотируемая орбитальная станция. Запущена в 1998 году. Находится на высоте около 400 км над Землёй.",
        "Теория относительности Эйнштейна включает специальную (1905) и общую (1915) теории. Описывает связь пространства, времени, массы и энергии. E=mc².",
        "ДНК (дезоксирибонуклеиновая кислота) — молекула, хранящая генетическую информацию. Имеет структуру двойной спирали, открытую в 1953 году.",
        "Атом состоит из ядра (протоны и нейтроны) и электронов. Протон имеет положительный заряд, электрон — отрицательный, нейтрон — нейтральный.",
        
        # === ГЕОГРАФИЯ ===
        "Москва — столица России, крупнейший город страны с населением более 12 миллионов человек. Основана в 1147 году.",
        "Санкт-Петербург — второй по величине город России, основан Петром I в 1703 году. Был столицей Российской империи с 1712 по 1918 год.",
        "Россия — крупнейшая страна мира по площади (17,1 млн км²). Население около 146 миллионов человек. Столица — Москва.",
        "Эверест (Джомолунгма) — высочайшая вершина мира, 8848 метров. Находится в Гималаях на границе Непала и Китая.",
        "Байкал — самое глубокое озеро в мире, глубина 1642 метра. Содержит около 20% мировых запасов пресной воды. Находится в Сибири.",
        "Амазонка — крупнейшая река мира по полноводности. Длина около 7000 км. Протекает в Южной Америке.",
        "Тихий океан — крупнейший океан Земли, площадь около 165 миллионов км². Максимальная глубина — Марианская впадина (около 11 000 м).",
        "Сахара — крупнейшая жаркая пустыня мира, площадь около 9 миллионов км². Находится в Северной Африке.",
        "Эйфелева башня построена в 1889 году в Париже. Высота 330 метров, названа в честь инженера Густава Эйфеля. Символ Франции.",
        "Великая Китайская стена — крупнейшее архитектурное сооружение в мире. Общая длина более 20 000 км. Строилась с III века до н.э.",
        
        # === БЫТОВЫЕ СОВЕТЫ ===
        "Чтобы сварить яйцо вкрутую, положите его в холодную воду, доведите до кипения и варите 10-12 минут.",
        "Чтобы сварить яйцо всмятку, положите его в кипящую воду и варите 3-4 минуты.",
        "Оптимальная температура в холодильнике — от 2 до 4 градусов Цельсия. В морозилке — минус 18°C.",
        "Рис варится в пропорции 1:2 (одна часть риса на две части воды) примерно 15-20 минут на медленном огне.",
        "Макароны варятся 8-12 минут в подсоленной воде. На 100 грамм макарон — 1 литр воды и щепотка соли.",
        "Чтобы убрать запах из микроволновки, нагрейте в ней стакан воды с лимоном 3-5 минут.",
        "Чтобы проверить свежесть яйца, опустите его в воду: свежее утонет, несвежее всплывёт.",
        "Оптимальная температура для стирки белого белья — 60°C, цветного — 30-40°C.",
        
        # === ЗДОРОВЬЕ ===
        "Взрослому человеку рекомендуется спать 7-9 часов в сутки для поддержания здоровья.",
        "Рекомендуемое потребление воды — около 2 литров в день, зависит от веса и физической активности.",
        "Нормальная температура тела человека — 36.6 градусов Цельсия, допустимы колебания от 36.1 до 37.2°C.",
        "Нормальное артериальное давление взрослого человека — 120/80 мм рт. ст. Повышенное — выше 140/90.",
        "Нормальный пульс взрослого человека в покое — 60-100 ударов в минуту. У спортсменов может быть ниже.",
        "Витамин C содержится в цитрусовых, киви, болгарском перце, чёрной смородине. Необходим для иммунитета.",
        "Витамин D вырабатывается в коже под действием солнца. Содержится в рыбе, яйцах. Важен для костей.",
        
        # === ТЕХНОЛОГИИ ===
        "Wi-Fi — технология беспроводной передачи данных. Работает на частотах 2.4 ГГц и 5 ГГц. Дальность до 100 метров.",
        "Bluetooth — стандарт беспроводной связи для передачи данных на короткие расстояния до 10-100 метров.",
        "SSD (твердотельный накопитель) быстрее HDD в 5-10 раз, не имеет движущихся частей, более надёжен.",
        "Оперативная память (RAM) — временное хранилище данных для быстрого доступа процессором. Очищается при выключении.",
        "Процессор (CPU) — центральный вычислительный компонент компьютера. Измеряется в герцах (ГГц) и количестве ядер.",
        "Видеокарта (GPU) — компонент для обработки графики. Используется в играх, видеомонтаже, машинном обучении.",
        "USB (Universal Serial Bus) — стандарт подключения устройств. USB 3.0 передаёт данные со скоростью до 5 Гбит/с.",
        "HDMI — интерфейс для передачи видео и аудио высокого разрешения. Поддерживает разрешение до 8K.",
    ]
    
    cursor = conn.cursor()
    for text in faq_items:
        cursor.execute(
            "INSERT INTO documents (text, source) VALUES (?, ?)",
            (text, "faq")
        )
    conn.commit()
    return len(faq_items)


def create_embeddings(conn: sqlite3.Connection, model: SentenceTransformer, device: str) -> np.ndarray:
    """Создаём embeddings для всех документов"""
    cursor = conn.cursor()
    cursor.execute("SELECT id, text FROM documents ORDER BY id")
    rows = cursor.fetchall()
    
    print(f"\nСоздаём embeddings для {len(rows)} документов...")
    
    texts = [row[1] for row in rows]
    ids = [row[0] for row in rows]
    
    # Для multilingual-e5 нужен префикс "query: " для запросов и "passage: " для документов
    texts_with_prefix = [f"passage: {text}" for text in texts]
    
    all_embeddings = []
    for i in tqdm(range(0, len(texts_with_prefix), BATCH_SIZE), desc="  Embedding"):
        batch = texts_with_prefix[i:i + BATCH_SIZE]
        embeddings = model.encode(
            batch,
            convert_to_numpy=True,
            normalize_embeddings=True,
            show_progress_bar=False,
            device=device
        )
        all_embeddings.append(embeddings)
    
    return np.vstack(all_embeddings).astype(np.float32)


def create_faiss_index(embeddings: np.ndarray, output_dir: Path) -> faiss.Index:
    """Создаём FAISS индекс и сохраняем сырые векторы"""
    print(f"\nСоздаём FAISS индекс ({embeddings.shape[0]} векторов, {embeddings.shape[1]} dims)...")
    
    # IndexFlatIP - точный поиск по косинусному сходству (для нормализованных векторов)
    index = faiss.IndexFlatIP(EMBEDDING_DIM)
    index.add(embeddings)
    
    # Сохраняем сырые векторы для мобильного приложения (простой бинарный формат)
    embeddings_path = output_dir / "rag_embeddings.bin"
    embeddings.tofile(str(embeddings_path))
    print(f"Сырые embeddings: {embeddings_path} ({embeddings_path.stat().st_size / 1024 / 1024:.1f} MB)")
    
    return index


def save_config(output_dir: Path, total_docs: int, num_vectors: int):
    """Сохраняем конфигурацию"""
    config = {
        "embedding_model": EMBEDDING_MODEL,
        "embedding_dim": EMBEDDING_DIM,
        "total_documents": total_docs,
        "num_vectors": num_vectors,
        "max_text_length": MAX_TEXT_LENGTH,
        "query_prefix": "query: ",
        "version": "1.0.0"
    }
    
    config_path = output_dir / "rag_config.json"
    with open(config_path, "w", encoding="utf-8") as f:
        json.dump(config, f, ensure_ascii=False, indent=2)
    
    print(f"Конфиг сохранён: {config_path}")


def main():
    print("=" * 60)
    print("RAG Index Creator for Nexus")
    print("=" * 60)
    
    # Setup
    device = setup_device()
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    
    db_path = OUTPUT_DIR / "rag_base.db"
    index_path = OUTPUT_DIR / "rag_index.faiss"
    
    # Удаляем старые файлы
    if db_path.exists():
        db_path.unlink()
    if index_path.exists():
        index_path.unlink()
    
    # 1. Создаём базу и загружаем данные
    print("\n[1/4] Создаём базу данных...")
    conn = create_database(db_path)
    
    print("\n[2/4] Загружаем датасеты...")
    total_docs = load_and_process_datasets(conn)
    total_docs += add_faq_data(conn)
    print(f"\nВсего документов: {total_docs}")
    
    # 2. Загружаем модель
    print(f"\n[3/4] Загружаем модель {EMBEDDING_MODEL}...")
    model = SentenceTransformer(EMBEDDING_MODEL, device=device)
    
    # 3. Создаём embeddings и индекс
    embeddings = create_embeddings(conn, model, device)
    index = create_faiss_index(embeddings, OUTPUT_DIR)
    
    # 4. Сохраняем
    print("\n[4/4] Сохраняем файлы...")
    faiss.write_index(index, str(index_path))
    print(f"FAISS индекс: {index_path} ({index_path.stat().st_size / 1024 / 1024:.1f} MB)")
    
    conn.close()
    print(f"SQLite база: {db_path} ({db_path.stat().st_size / 1024 / 1024:.1f} MB)")
    
    save_config(OUTPUT_DIR, total_docs, embeddings.shape[0])
    
    # Итог
    print("\n" + "=" * 60)
    print("ГОТОВО!")
    print("=" * 60)
    print(f"Файлы в папке: {OUTPUT_DIR}")
    print("\nЗагрузите эти файлы в Selectel:")
    print(f"  1. {db_path.name}")
    print(f"  2. {index_path.name}")
    print(f"  3. rag_embeddings.bin")
    print(f"  4. rag_config.json")


if __name__ == "__main__":
    main()
