// Explore filter sheet (FilterSheet / SelectCitySheet / NewAreaSheet in ExploreView.swift).
import { $, esc, icon } from './util.js';
import * as St from './store.js';
import { S } from './store.js';
import { sheet, chip, toast, confirmSheet, makeMap } from './ui.js';
import { ex, saveEx, areas, saveAreas, cityAreas, selectedArea, TIERS, activeCount, clearFilters, rectangle, studioInArea } from './filters.js';

const gl = (label, on, attrs) => chip(label, on, attrs).replace('class="chip"', 'class="chip glassy"');
const FEW = 9;

/** `view`: the Explore view (its `cat`, `href()` and `refresh()`), so the sheet and the page stay in step. */
export function openFilters(view) {
  let all = false;
  const area = () => selectedArea(areas, ex.areaId, S.settings.cityId);
  const count = () => activeCount(ex, !!view.cat, area());
  const apply = () => { saveEx(); view.refresh(); draw(); };
  const s = sheet('Filter', '', { trailing: '<button class="glass-btn txt" data-clear>Clear</button>' });
  const draw = () => {
    const cats = [...S.categories].sort((a, b) => a.title.localeCompare(b.title, 'sv'));
    const mine = cityAreas(areas, S.settings.cityId), cur = area();
    s.el.querySelector('[data-clear]').disabled = !count();
    s.body.innerHTML =
      '<h3 class="sec-title">STUDIO ACCESS</h3><div class="chips wrap">' + TIERS.map((t) => gl(t, ex.tiers.includes(t), 'data-tier="' + t + '"')).join('') + '</div>' +
      '<h3 class="sec-title">DISPLAY OPTIONS</h3><div class="chips wrap">' + gl('Favorite studios', ex.favs, 'data-opt="favs"') + gl('Solo training only', ex.solo, 'data-opt="solo"') + gl('Hide full classes', ex.free, 'data-opt="free"') + '</div>' +
      '<div class="sec-row"><h3 class="sec-title">AREA <small>' + esc(St.city().name) + '</small></h3><button class="link" data-city>Change city</button></div>' +
      '<div class="chips wrap">' + gl('Entire ' + esc(St.city().name), !cur, 'data-area=""') + mine.map((a) => gl(icon('map') + esc(a.name), cur && cur.id === a.id, 'data-area="' + esc(a.id) + '"')).join('') +
      gl(icon('plus') + 'New area', false, 'data-newarea') + '</div>' +
      (cur ? '<p class="area-note muted small">' + esc(cur.name) + ' covers ' + covered(cur) + ' studios. <button class="link" data-delarea>Delete area</button></p>' : '') +
      '<div class="sec-row"><h3 class="sec-title">CATEGORIES</h3><button class="link" data-all>' + (all ? 'Show less' : 'Show all') + '</button></div>' +
      '<div class="chips wrap">' + (all ? cats : cats.slice(0, FEW)).map((c) => gl(esc(c.title), view.cat && view.cat.id === c.id, 'data-cat="' + c.id + '"')).join('') + '</div>' +
      '<button class="btn lime sheet-go" data-close>Show results</button>';
  };
  const covered = (a) => St.cityStudios().filter((x) => x.lat && x.lon && studioInArea(x, a)).length;
  s.body.addEventListener('click', async (e) => {
    const t = e.target.closest('[data-tier],[data-opt],[data-area],[data-cat],[data-all],[data-city],[data-newarea],[data-delarea]');
    if (!t) return;
    const d = t.dataset;
    if ('tier' in d) ex.tiers = ex.tiers.includes(d.tier) ? ex.tiers.filter((x) => x !== d.tier) : ex.tiers.concat(d.tier);
    else if ('opt' in d) ex[d.opt] = !ex[d.opt];
    else if ('area' in d) ex.areaId = d.area && ex.areaId !== d.area ? d.area : null;
    else if ('all' in d) { all = !all; draw(); return; }
    else if ('city' in d) { cityPicker(s, draw); return; }
    else if ('newarea' in d) { newArea(() => { apply(); }); return; }
    else if ('delarea' in d) {
      const a = area();
      if (a && await confirmSheet('Delete “' + a.name + '”?', 'The area is removed from your saved areas.', 'Delete')) { areas.splice(areas.indexOf(a), 1); saveAreas(); ex.areaId = null; apply(); }
      return;
    } else if ('cat' in d) {
      const id = +d.cat;
      const onHash = () => { window.removeEventListener('hashchange', onHash); setTimeout(draw, 0); };
      window.addEventListener('hashchange', onHash);
      location.hash = view.href({ cat: view.cat && view.cat.id === id ? null : id });
      return;
    }
    apply();
  });
  s.el.querySelector('[data-clear]').addEventListener('click', () => {
    clearFilters(ex);
    if (view.cat) { const onHash = () => { window.removeEventListener('hashchange', onHash); setTimeout(draw, 0); }; window.addEventListener('hashchange', onHash); location.hash = view.href({ cat: null }); }
    apply();
  });
  draw();
}

/** "Change city": the city list inside the sheet; picking one switches city and closes the sheet. */
function cityPicker(s, back) {
  s.body.innerHTML = '<button class="link" data-back>' + icon('back') + ' Filter</button><h3 class="sec-title">CITY</h3><div class="card menu">' +
    (S.cities.length ? S.cities : [St.city()]).map((c) => '<button class="mrow" data-id="' + c.id + '"><b class="grow">' + esc(c.name) + '</b>' + (c.id === S.settings.cityId ? icon('check') : '') + '</button>').join('') + '</div>';
  s.body.querySelector('[data-back]').addEventListener('click', back);
  s.body.querySelectorAll('[data-id]').forEach((b) => b.addEventListener('click', () => {
    if (+b.dataset.id !== S.settings.cityId) { St.selectCity(b.dataset.id); toast('City set to ' + St.city().name); }
    s.close();
  }));
}

/** "New area": tap the map to outline a region, or just save the visible map region. */
function newArea(done) {
  const pts = [];
  const nameDefault = 'My area ' + (cityAreas(areas, S.settings.cityId).length + 1);
  const a = sheet('New area', '<label class="form"><span>Name</span><input id="na-name" type="text" maxlength="40" value="' + esc(nameDefault) + '"></label>' +
    '<p class="muted small" id="na-hint">Tap the map to outline the area, or save as is to use the visible region.</p><div class="map na-map"></div>' +
    '<div class="stack"><button class="btn lime" data-save>Save area</button><button class="btn glass" data-undo disabled>Undo last point</button></div>');
  const c = St.city().coordinates;
  const box = a.el.querySelector('.na-map');
  let m, shape;
  makeMap(box, St.cityStudios(), { center: c ? [c.latitude, c.longitude] : [59.33, 18.07] }).then((r) => {
    if (!r) return;
    m = r.map;
    m.on('click', (ev) => { pts.push({ lat: ev.latlng.lat, lon: ev.latlng.lng }); drawShape(); });
  });
  const drawShape = () => {
    if (shape) shape.remove();
    const ll = pts.map((p) => [p.lat, p.lon]);
    shape = ll.length > 2 ? window.L.polygon(ll, { color: '#7a9c00' }).addTo(m) : window.L.polyline(ll, { color: '#7a9c00' }).addTo(m);
    a.el.querySelector('[data-undo]').disabled = !pts.length;
    a.el.querySelector('#na-hint').textContent = pts.length < 3 ? 'Add at least 3 points to outline an area, or save to use the visible region.' : pts.length + ' points.';
  };
  a.el.querySelector('[data-undo]').addEventListener('click', () => { pts.pop(); drawShape(); });
  a.el.querySelector('[data-save]').addEventListener('click', () => {
    let points = pts;
    if (pts.length < 3) {
      if (!m) { toast('The map is unavailable'); return; }
      const b = m.getBounds();
      points = rectangle({ north: b.getNorth(), south: b.getSouth(), east: b.getEast(), west: b.getWest() });
    }
    const name = $('#na-name', a.el).value.trim() || nameDefault;
    const id = 'a' + Date.now().toString(36);
    areas.push({ id, name, cityId: S.settings.cityId, points: points.slice(), createdAt: Date.now() });
    saveAreas(); ex.areaId = id;
    toast('Area “' + name + '” saved');
    a.close(); done();
  });
}
