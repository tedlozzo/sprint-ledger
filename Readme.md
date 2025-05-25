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
Article about this code - https://tedlozzo.substack.com/p/colours-of-backlog 
Backlog Color Coding - https://www.infoq.com/news/2010/05/what-color-backlog/
Apache Mesos JIRA Dataset - https://www.kaggle.com/datasets/tedlozzo/apache-jira-mesos-project 
Sentence Transformers - https://sbert.net/ 

## 📌 Notes
This script works best on large, historic backlogs
Models may disagree — that’s a feature, not a bug
Combine results using consensus logic (e.g., 3+ models agree = strong signal)