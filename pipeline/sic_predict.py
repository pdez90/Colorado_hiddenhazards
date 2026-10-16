import pickle, re, collections
M=pickle.load(open('work/inv/sic_clf.pkl','rb'))
from sic_classifier_norm import norm
def predict(texts):
    X=M['vec'].transform([norm(t) for t in texts])
    D,I=M['nn'].kneighbors(X)
    out=[]
    for d,i in zip(D,I):
        sc=collections.Counter()
        for dd,ii in zip(d,i): sc[M['labels'][ii]]+=(1-dd)*(M['w'][ii]**0.3)
        c,s=sc.most_common(1)[0]
        out.append((c,1-d[0],M['docs'][i[0]]))
    return out
