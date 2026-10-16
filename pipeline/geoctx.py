import re
COUNTIES={'ADAMS','ALAMOSA','ARAPAHOE','ARCHULETA','BACA','BENT','BOULDER','BROOMFIELD','CHAFFEE','CHEYENNE','CLEAR CREEK','CONEJOS','COSTILLA','CROWLEY','CUSTER','DELTA','DENVER','DOLORES','DOUGLAS','EAGLE','ELBERT','EL PASO','FREMONT','GARFIELD','GILPIN','GRAND','GUNNISON','HINSDALE','HUERFANO','JACKSON','JEFFERSON','KIOWA','KIT CARSON','LAKE','LA PLATA','LARIMER','LAS ANIMAS','LINCOLN','LOGAN','MESA','MINERAL','MOFFAT','MONTEZUMA','MONTROSE','MORGAN','OTERO','OURAY','PARK','PHILLIPS','PITKIN','PROWERS','PUEBLO','RIO BLANCO','RIO GRANDE','ROUTT','SAGUACHE','SAN JUAN','SAN MIGUEL','SEDGWICK','SUMMIT','TELLER','WASHINGTON','WELD','YUMA'}
BOTH={'DENVER','PUEBLO','BOULDER','GUNNISON','OURAY','DOLORES','KIOWA','ELBERT','CROWLEY','LAKE','MESA','DELTA','EAGLE','PARK','SAGUACHE','LA PLATA','BROOMFIELD'}
CITIES=set(open('work/inv/co_cities.txt').read().split('\n'))
def clean(t):
    u=re.sub(r"[^A-Z \-\.'\(\)]","",t.upper())
    u=re.sub(r"\(SEE ALSO.*","",u)
    u=re.sub(r"\(.*?COUNTY\)","",u)
    u=re.sub(r"[\(\)]","",u)
    u=re.sub(r"\s+"," ",u).strip(" -.")
    return u
def heading(t):
    """return ('county',name) / ('city',name) / ('both',name) / None"""
    if re.search(r"\d",t): return None
    if len(t.split())>4: return None
    u=clean(t)
    if len(u)<3 or len(u)>30: return None
    u2=re.sub(r"\s+COUNTY$","",u)
    if u2 in COUNTIES:
        if u.endswith('COUNTY') or u2 not in BOTH: return ('county',u2)
        return ('both',u2)
    if u in CITIES: return ('city',u)
    return None
