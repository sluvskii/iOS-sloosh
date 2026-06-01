import { parseCollapsCatalog } from '@/native/collaps-parser';

import { buildAllohaSeriesCatalogFromApi } from './alloha';

export async function resolveCatalog(source: string, mediaId: string, embedHtml: string) {
  if (source !== 'alloha') {
    return parseCollapsCatalog(embedHtml);
  }

  // Fetches series catalog for TV shows, movie catalog for films (via translation_iframe)
  return buildAllohaSeriesCatalogFromApi(mediaId);
}
