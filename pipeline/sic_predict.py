import pickle, re, collections
from sic_classifier_norm import norm
M=None
def load(path='work/inv/sic_clf.pkl'):
    """Load the description->SIC model (trained by sic_classifier.py); loaded on first use so the module imports cleanly."""
    global M
    M=pickle.load(open(path,'rb'))
    return M
def predict(texts):
    if M is None: load()
    X=M['vec'].transform([norm(t) for t in texts])
    D,I=M['nn'].kneighbors(X)
    out=[]
    for d,i in zip(D,I):
        sc=collections.Counter()
        for dd,ii in zip(d,i): sc[M['labels'][ii]]+=(1-dd)*(M['w'][ii]**0.3)
        c,s=sc.most_common(1)[0]
        out.append((c,1-d[0],M['docs'][i[0]]))
    return out
