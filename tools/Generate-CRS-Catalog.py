#!/usr/bin/env python3
"""Generate immutable metadata (never projection parameters) from pinned NGA proj.db.
Usage: python3 tools/Generate-CRS-Catalog.py [proj.db path]
State Plane membership joins EPSG projected_crs -> conversion. Recognize official
SPCS83 / <state> CS27 conversion families, then validate their jurisdiction against
all 50 US states and the EPSG Puerto Rico/Virgin Islands labels. This deliberately
excludes local grids, UTM, statewide non-SPCS systems and CRS-name lookalikes.
"""
import hashlib, json, pathlib, re, sqlite3, sys
root = pathlib.Path(__file__).resolve().parent.parent
check = '--check' in sys.argv
args = [a for a in sys.argv[1:] if a != '--check']
db = pathlib.Path(args[0]) if args else root/'RoadStationApp/CRSAdapter/.build/checkouts/projections-ios/proj-ios/Resources/proj.db'
c = sqlite3.connect(f'file:{db}?mode=ro', uri=True)
c.row_factory = sqlite3.Row
states = 'Alabama|Alaska|Arizona|Arkansas|California|Colorado|Connecticut|Delaware|Florida|Georgia|Hawaii|Idaho|Illinois|Indiana|Iowa|Kansas|Kentucky|Louisiana|Maine|Maryland|Massachusetts|Michigan|Minnesota|Mississippi|Missouri|Montana|Nebraska|Nevada|New Hampshire|New Jersey|New Mexico|New York|North Carolina|North Dakota|Ohio|Oklahoma|Oregon|Pennsylvania|Rhode Island|South Carolina|South Dakota|Tennessee|Texas|Utah|Vermont|Virginia|Washington|West Virginia|Wisconsin|Wyoming|Puerto Rico & Virgin Islands|Puerto Rico|St. Croix'.split('|')
# Six historical conversion identities use other official naming families.
# Michigan EPSG conversions explicitly say State Plane; Arizona EPSG conversions
# name the same three CS27 zones documented by NGS SPCS27 (0201/0202/0203).
# Keep exact conversion identity/name checks rather than guessing from CRS names.
legacy = {10201:'Arizona Coordinate System East zone',10202:'Arizona Coordinate System Central zone',10203:'Arizona Coordinate System West zone',
          12101:'Michigan State Plane East zone',12102:'Michigan State Plane Old Central zone',12103:'Michigan State Plane West zone'}
def stateplane(conversion, conversion_code):
    if not conversion: return None
    if conversion.startswith('SPCS83 '): label = conversion[7:].split(' (')[0]
    elif ' CS27' in conversion: label = conversion.replace(' CS27', '')
    elif conversion_code in legacy:
        assert conversion == legacy[conversion_code], 'Historical membership metadata changed'
        label = conversion.replace(' Coordinate System', '').replace(' State Plane', '')
    else: return None
    for state in sorted(states, key=len, reverse=True):
        if label == state or label.startswith(state+' '):
            return dict(state=state, zone=label, conversion=conversion)
    raise ValueError('Unrecognized State Plane jurisdiction: '+conversion)
entries=[]
for table, projected in [('projected_crs',True),('geodetic_crs',False)]:
    rows=c.execute(f'''select p.* from {table} p join coordinate_system s on s.auth_name=p.coordinate_system_auth_name and s.code=p.coordinate_system_code
        where p.auth_name='EPSG' and s.dimension=2 '''+('' if projected else "and p.type='geographic 2D'" )+' order by cast(p.code as integer)').fetchall()
    for p in rows:
        axes=c.execute('''select u.auth_name,u.code,u.name,u.type from axis a join unit_of_measure u on u.auth_name=a.uom_auth_name and u.code=a.uom_code
            where a.coordinate_system_auth_name=? and a.coordinate_system_code=? order by a.coordinate_system_order''',(p['coordinate_system_auth_name'],p['coordinate_system_code'])).fetchall()
        # Only Earth horizontal two-axis systems; mixed native axes are incompatible.
        geo=c.execute('select * from geodetic_crs where auth_name=? and code=?',(p['geodetic_crs_auth_name'],p['geodetic_crs_code'])).fetchone() if projected else p
        datum=c.execute('select name,ellipsoid_auth_name,ellipsoid_code from geodetic_datum where auth_name=? and code=?',(geo['datum_auth_name'],geo['datum_code'])).fetchone() if geo else None
        if not datum: continue
        earth=c.execute('''select b.name from ellipsoid e join celestial_body b on b.auth_name=e.celestial_body_auth_name and b.code=e.celestial_body_code where e.auth_name=? and e.code=?''',(datum[1],datum[2])).fetchone()
        if not earth or earth[0]!='Earth': continue
        unit={'9001':'meter','9002':'internationalFoot','9003':'usSurveyFoot','9122':'degree','9102':'degree'}.get(str(axes[0]['code'])) if len(axes)==2 and all(a['auth_name']=='EPSG' and a['code']==axes[0]['code'] for a in axes) else None
        areas=[dict(name=e['description'],west=e['west_lon'],south=e['south_lat'],east=e['east_lon'],north=e['north_lat']) for e in c.execute('''select e.* from usage u join extent e on e.auth_name=u.extent_auth_name and e.code=u.extent_code
            where u.object_table_name=? and u.object_auth_name='EPSG' and u.object_code=? order by e.code''',(table,p['code'])) if all(e[k] is not None for k in ['west_lon','east_lon','south_lat','north_lat'])]
        conversion=c.execute('select name,code from conversion where auth_name=? and code=?',(p['conversion_auth_name'],p['conversion_code'])).fetchone() if projected else None
        entries.append(dict(code=int(p['code']),name=p['name'],datum=datum[0],nativeUnit=unit or 'unsupported',nativeUnitName=axes[0]['name'] if axes else 'Unknown',areas=areas,projected=projected,deprecated=bool(p['deprecated']),statePlane=stateplane(conversion[0],conversion[1]) if conversion else None))
metadata=dict(c.execute('select * from metadata'))
result=dict(databaseSHA256=hashlib.sha256(db.read_bytes()).hexdigest(),epsgVersion=metadata['EPSG.VERSION'],entries=entries)
out=root/'RoadStationApp/CRSAdapter/Sources/RoadStationCRSCatalog/Resources/catalog.json'
encoded = json.dumps(result,ensure_ascii=False,sort_keys=True,separators=(',',':'))+'\n'
if check:
    assert out.read_text() == encoded, 'Catalog differs from pinned proj.db; regenerate and review'
else:
    out.write_text(encoded)
sp=[e for e in entries if e['statePlane']]
assert all(any(e['statePlane']['state']==s for e in sp) for s in states[:50])
print(f'{len(entries)} horizontal EPSG entries; {len(sp)} State Plane entries; {len(set(e["statePlane"]["state"] for e in sp))} jurisdictions; EPSG {metadata["EPSG.VERSION"]}')
