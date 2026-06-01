export type CarouselItem = {
  id: string;
  title: string;
  subtitle: string;
};

export const heroItem: CarouselItem = {
  id: 'hero-1',
  title: 'Caminandes: Llamigos',
  subtitle: 'Animation, Comedy, Family',
};

export const popularItems: CarouselItem[] = [
  { id: 'p1', title: 'Dracula', subtitle: '1931' },
  { id: 'p2', title: 'Sahara', subtitle: '1943' },
  { id: 'p3', title: 'Nosferatu', subtitle: '1922' },
];

export const topFilmItems: CarouselItem[] = [
  { id: 'f1', title: 'The Godfather', subtitle: 'Top 250' },
  { id: 'f2', title: 'Interstellar', subtitle: 'Top 250' },
  { id: 'f3', title: 'Pulp Fiction', subtitle: 'Top 250' },
];

export const topSeriesItems: CarouselItem[] = [
  { id: 's1', title: 'Breaking Bad', subtitle: 'Top TV' },
  { id: 's2', title: 'Chernobyl', subtitle: 'Top TV' },
  { id: 's3', title: 'Sherlock', subtitle: 'Top TV' },
];
