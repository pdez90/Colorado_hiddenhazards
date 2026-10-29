import json, glob, re, collections, pickle
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.neighbors import NearestNeighbors
def norm(t):
    t=t.upper(); t=re.sub(r"[^A-Z ]"," ",t); t=re.sub(r"\bN ?E ?C\b"," ",t)
    return re.sub(r"\s+"," ",t).strip()
def train(parsed_glob='work/parsed/*.jsonl'):
    """Description -> SIC model from the editions that print codes (1967-1986): the modal code of every frequent
    printed description, indexed by character n-grams for nearest-neighbour lookup (sic_predict.predict)."""
    pairs=collections.Counter()
    for f in glob.glob(parsed_glob):
        for l in open(f):
            r=json.loads(l)
            for c,d in zip(r.get('sic',[]),r.get('sic_desc',[])):
                if c and d and r['year']>=1967 and r['year']<=1986:
                    pairs[(c,norm(d))]+=1
    # keep frequent description-code pairs, and the modal code per description
    bydesc=collections.defaultdict(collections.Counter)
    for (c,d),n in pairs.items():
        if len(d)>=4: bydesc[d][c]+=n
    codecount=collections.Counter()
    for (c,d),n in pairs.items(): codecount[c]+=n
    docs=[];labels=[];w=[]
    for d,cc in bydesc.items():
        c,n=cc.most_common(1)[0]
        if n>=2 and codecount[c]>=5:
            docs.append(d); labels.append(c); w.append(n)
    vec=TfidfVectorizer(analyzer='char_wb',ngram_range=(3,5),min_df=1,sublinear_tf=True)
    X=vec.fit_transform(docs)
    nn=NearestNeighbors(n_neighbors=5,metric='cosine').fit(X)
    return dict(vec=vec,nn=nn,labels=labels,docs=docs,w=w)
def main():
    model=train()
    pickle.dump(model,open('work/inv/sic_clf.pkl','wb'))
    print(len(model['docs']),'training descriptions', len(set(model['labels'])),'codes')
if __name__=='__main__': main()
