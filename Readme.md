# 🟥🟨🟩⬛ Backlog Color Classifier

This project uses multiple sentence-transformer models to classify JIRA tickets by their delivery intent and quality impact. Based on Philippe Kruchten's color-coding framework, tickets are categorized into:

- 🟩 **Green:** User-visible features
- 🟥 **Red:** Defects and bugs
- 🟨 **Yellow:** Improvements, documentation, performance tuning
- ⬛ **Black:** Technical debt and invisible risks

## 🚀 How it Works

- JIRA issue data is queried using DuckDB
- Ticket metadata (`summary`, `description`, `issuetype`) is combined into a single input text
- Five pre-trained models classify each ticket using zero-shot similarity
- Final result includes predictions per model

## 🧠 Requirements

- Python 3.8+
- `sentence-transformers`
- `duckdb`
- `pandas`

Install with:
```bash
pip install -r requirements.txt
```

## 🧪 Run the Script

`python main.py`

This will:

* Load and run the DuckDB SQL query
* Apply five classification models
* Save predictions into a CSV file

## 📚 References

Backlog Color Coding

Apache Mesos JIRA Dataset

Sentence Transformers

## 📌 Notes
This script works best on large, historic backlogs
Models may disagree — that’s a feature, not a bug
Combine results using consensus logic (e.g., 3+ models agree = strong signal)