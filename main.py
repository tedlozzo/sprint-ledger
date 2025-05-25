import os
import logging
import duckdb
import pandas as pd
from sentence_transformers import SentenceTransformer, util

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)
LABEL_TEXTS = {
    "green": (
        "Work that delivers visible and positive business value. "
        "This includes user-facing features, APIs, CLI commands, or functional capabilities requested by external stakeholders. "
        "Also includes backend functionality changes that introduce new behavior, such as upgrading default components or implementing new workflows."
        "Examples: new features, extended functionality, enhancements visible to users or integrators."
    ),

    "red": (
        "Work that resolves a visible and user-impacting problem in the system. "
        "Examples: broken behavior, crashes, misbehaving components, runtime errors, or regressions. "
        "This - Usually involves fixing production code or patching functionality."
        "Usually involves fixing broken behavior that exists in production code."
        "Does NOT include writing new tests for known cases or improving test coverage."
        "Does NOT include documentation tasks or tickets that describe an issue to be explained rather than fixed."
    ),

    "yellow": (
        "Work that improves the internal quality, architecture, or maintainability of the system. "
        "This includes performance enhancements, scalability efforts, refactors, internal tools, or writing documentation "
        "that clarifies complex logic, setup, or developer workflows. "
        "Even if it refers to a known issue, the goal is to explain, structure, or improve — not patch."
        "Includes adding integration tests, improving test reliability, tuning configurations, and restructuring internal logic."
    ),

    "black": (
        "Invisible and negative work caused by shortcuts or past decisions. "
        "Examples: technical debt, missing tests, deprecated APIs, unstable components, or quick fixes without long-term support. "
        "This type of work often becomes visible later due to its impact on stability or maintainability."
        "Includes writing missing tests for important components or failure cases that were previously untested."
    )
}

MODEL_NAMES = [
    "all-MiniLM-L6-v2",
    "all-mpnet-base-v2",
    "paraphrase-MiniLM-L3-v2",
    "BAAI/bge-large-en-v1.5",
    "sentence-t5-base",
]

def format_text(model_name, text):
    if "bge" in model_name:
        return f"Represent this sentence for classification: {text}"
    elif "e5" in model_name:
        return f"passage: {text}"
    return text

def classify_tickets(df):
    for model_name in MODEL_NAMES:
        logger.info(f"Loading model: {model_name}")
        model = SentenceTransformer(model_name)

        label_embeds = {
            label: model.encode(format_text(model_name, desc), convert_to_tensor=True)
            for label, desc in LABEL_TEXTS.items()
        }

        def classify(text):
            emb = model.encode(format_text(model_name, text), convert_to_tensor=True)
            similarities = {
                label: util.cos_sim(emb, ref)[0].item() for label, ref in label_embeds.items()
            }
            return max(similarities, key=similarities.get)

        col_name = f"predicted_{model_name.split('/')[-1]}"
        df[col_name] = df['text'].apply(classify)
    return df

def load_data():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    sql_path = os.path.join(script_dir, "sql", "extract-sprint-and-description.sql")
    result_path = os.path.join(script_dir, "classified_backlog_all_models.csv")

    con = duckdb.connect()
    with open(sql_path, "r", encoding="utf-8") as file:
        query = file.read()

    df = con.execute(query).df()
    logger.info(f"Loaded {len(df)} rows from DuckDB.")
    return df, result_path

def main():
    try:
        df, output_path = load_data()
        df = classify_tickets(df)
        df.drop(columns=['text'], inplace=True)
        df.to_csv(output_path, index=False)
        logger.info(f"✅ All classifications saved to '{output_path}'")
    except Exception as e:
        logger.warning(f"Classification pipeline failed: {e}")

if __name__ == "__main__":
    main()