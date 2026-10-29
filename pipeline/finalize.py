import pandas as pd, numpy as np
def confidence(geo_level,industry_evidence):
    """high = street-level geocode AND industry code printed in the directory; medium = one of the two; low = neither."""
    g=pd.Series(geo_level); e=pd.Series(industry_evidence)
    return np.select([(g=='address')&(e=='printed'),(g=='address')|(e=='printed')],['high','medium'],'low')
def main():
    df=pd.read_pickle('work/inv/records_final.pkl'); s=pd.read_pickle('work/inv/sites.pkl')
    # site-level SIC evidence quality: any hazardous record at site with directory-printed code
    hz=df[df.site_id.notna() & (df.fe_hazard|df.ext_hazard)]
    ev=hz.groupby('site_id').sic_source.agg(lambda x: 'printed' if x.isin(['directory','naics']).any() else 'inferred')
    s['industry_evidence']=s.site_id.map(ev).fillna('inferred')
    s['confidence']=confidence(s.geo_level.values,s.industry_evidence.values)
    # county via zip
    zco=pd.read_csv('work/inv/zip_county.csv',dtype=str); zmap=dict(zip(zco.z,zco.COUNTY_NAME))
    s['county']=s.zip.map(zmap).fillna('')
    s['hazard_span_years']=s.hazard_years.apply(lambda x: (int(x.split(';')[-1])-int(x.split(';')[0])) if x else 0)
    s['churn_hazard_firms']=s.n_hazard_establishments
    s.to_pickle('work/inv/sites_final.pkl')
    H=s[s.fe_hazard]
    print(H.groupby('radar_status').confidence.value_counts().unstack(fill_value=0).to_string())
    print('hidden high-conf',((H.radar_status.str.startswith('6'))&(H.confidence=='high')).sum())
    print('sites with >=2 hazardous firms over time',(H.n_hazard_establishments>=2).sum())
    print(H[H.radar_status.str.startswith('6')].county.value_counts().head(10).to_string())
    # unlocated hazardous establishments
    u=df[(df.fe_hazard)&(~df.located)]
    print('unlocated F&E establishment-years',len(u),'establishments',u.estab_id.nunique())
if __name__=='__main__': main()
