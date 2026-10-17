"""Write data/geocoder/geocode_keys_with_python_results.csv: every address key the pipeline geocoded (normalised street,
town, ZIP) with the Python geocoder's result, so R/compare_with_python.R can check the R geocoder key by key."""
import pandas as pd
df = pd.read_pickle('work/inv/records_linked.pkl')
geo = pd.read_csv('work/geo/tiger_results.csv')
k = df.drop_duplicates('geo_key')[['geo_key', 'street_n', 'city_g', 'zip5']].rename(columns={'street_n': 'street', 'city_g': 'city', 'zip5': 'zip'})
k = k.merge(geo.rename(columns={'lat': 'lat_py', 'lon': 'lon_py', 'geo_quality': 'quality_py'}), on='geo_key', how='inner')
k.to_csv('data/geocoder/geocode_keys_with_python_results.csv', index=False)
print(len(k), 'address keys')
