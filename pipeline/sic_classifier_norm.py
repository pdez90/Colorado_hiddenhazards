"""The one text normalisation of the description -> SIC classifier, used for the training descriptions
(sic_classifier.train) and for the query text (sic_predict.predict). Two copies of this function had drifted apart
(training kept ' AND ', queries dropped it), so 'BREAD AND CAKE' at query time never met its own training n-grams."""
import re
def norm(t):
    t=t.upper(); t=re.sub(r"[^A-Z ]"," ",t); t=re.sub(r"\bN ?E ?C\b"," ",t)
    t=re.sub(r"\bAND\b"," ",t)          # 'AND', '&' and '+' are interchangeable in the printed descriptions ('&', '+' are dropped above)
    return re.sub(r"\s+"," ",t).strip()
