import re
def norm(t):
    t=t.upper(); t=re.sub(r"[^A-Z ]"," ",t); t=re.sub(r"\bN ?E ?C\b"," ",t)
    t=t.replace(' AND ',' ').replace('&',' ')
    return re.sub(r"\s+"," ",t).strip()
