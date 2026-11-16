import assert from 'node:assert/strict';
import { executeSearch, executeSuggestions } from './src/search/service';
import { dictionarySuggestions, fuzzyTitleCandidates } from './src/search/vocabulary';

// Controlled reproduction on the MERGED server source. This intentionally
// models an upstream which finds a title by prefix but not its full spelling.
// It does NOT assert that the live upstream behaves identically or why.
const title = 'Человек-паук: Новый день';
let calls = 0;
globalThis.fetch = async (input: any) => {
  const url = new URL(typeof input === 'string' ? input : input.url);
  assert.equal(url.hostname, 'catalog.invalid', 'Live network access is forbidden');
  calls++;
  const query = url.searchParams.get('query')?.toLowerCase();
  const results = query === 'человек-паук' ? [{
    id: 999001, media_type: 'movie', title, original_title: 'Spider-Man: Brand New Day',
    release_date: '2026-07-31', poster_path: null, vote_average: 0,
  }] : [];
  return Response.json({ page: 1, total_pages: 1, total_results: results.length, results });
};
const short = await executeSearch({ query: 'Человек-паук' });
assert.equal(short.data?.results[0].title, title);
assert.equal(dictionarySuggestions(title)[0].matchedBy, 'exact');
assert.equal(fuzzyTitleCandidates(title).length, 0, 'Exact keys are deliberately excluded from typo candidates');
const suggested = await executeSuggestions({ query: title });
assert.equal(suggested.data?.suggestions[0].id, '999001');
assert.equal(suggested.data?.suggestions[0].type, 'movie');
const full = await executeSearch({ query: title });
assert.equal(full.status, 200);
assert.equal(full.data?.results.length, 0);
console.log('REPRODUCED on d6a0b1f: prefix hit + exact typed suggestion + empty full-title search.');
console.log(`Mock catalog calls: ${calls}. No live catalog/auth/device behavior tested.`);
