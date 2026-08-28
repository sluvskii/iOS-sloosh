using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;

namespace EmpiricalTests
{
    // MARK: - Models
    public class AllohaTranslation
    {
        public string Name { get; set; } = "";
        public string IframeUrl { get; set; } = "";
        public string? StreamUrl { get; set; }

        public AllohaTranslation(string name, string iframeUrl, string? streamUrl = null)
        {
            Name = name;
            IframeUrl = iframeUrl;
            StreamUrl = streamUrl;
        }
    }

    public class AllohaEpisode
    {
        public int Episode { get; set; }
        public List<AllohaTranslation> Translations { get; set; } = new();
    }

    public class AllohaSeason
    {
        public int Season { get; set; }
        public List<AllohaEpisode> Episodes { get; set; } = new();
    }

    public class AllohaMovie
    {
        public List<AllohaTranslation> Translations { get; set; } = new();
    }

    public class AllohaApiResult
    {
        public bool IsSerial { get; set; }
        public AllohaMovie? Movie { get; set; }
        public List<AllohaSeason> Seasons { get; set; } = new();
    }

    // MARK: - Matching & Normalization (Mirroring AllohaRepository.swift lines 70-135)
    public static class AllohaMatching
    {
        public static string NormalizedAllohaTranslationName(string? name)
        {
            if (string.IsNullOrEmpty(name)) return "";
            string val = name;
            val = val.Replace("(Russian)", "")
                     .Replace("AC3 51 @ 640 kbps - Blu-ray CEE", "")
                     .Replace("AC3 5.1 @ 640 kbps", "")
                     .Replace("DUB", "Дубляж")
                     .Replace("MVO", "Многоголосый")
                     .Replace("DVO", "Двухголосый")
                     .Replace("AVO", "Авторский")
                     .Replace("ПМ", "Проф. многоголосый")
                     .Replace("ПД", "Проф. двухголосый")
                     .Replace("ЛМ", "Люб. многоголосый")
                     .Replace("ЛД", "Люб. двухголосый")
                     .Replace("[", " ")
                     .Replace("]", " ")
                     .Replace("(", " ")
                     .Replace(")", " ")
                     .Replace("|", " ")
                     .Trim();

            while (val.StartsWith("-") || val.StartsWith(","))
            {
                val = val.Substring(1).Trim();
            }
            while (val.EndsWith("-") || val.EndsWith(","))
            {
                val = val.Substring(0, val.Length - 1).Trim();
            }

            val = Regex.Replace(val, @"\s+", " ").Trim();
            return val;
        }

        public static bool AllohaTranslationNamesMatch(string? lhs, string? rhs, bool exactOnly = false)
        {
            string left = NormalizedAllohaTranslationName(lhs).ToLowerInvariant();
            string right = NormalizedAllohaTranslationName(rhs).ToLowerInvariant();
            if (string.IsNullOrEmpty(left) || string.IsNullOrEmpty(right)) return false;

            if (left == right) return true;

            var leftWords = new HashSet<string>(Regex.Split(left, @"[^a-zA-Z0-9\u0400-\u04FF]+").Where(w => w.Length > 2));
            var rightWords = new HashSet<string>(Regex.Split(right, @"[^a-zA-Z0-9\u0400-\u04FF]+").Where(w => w.Length > 2));

            if (leftWords.Count > 0 && rightWords.Count > 0)
            {
                if (leftWords.SetEquals(rightWords) || leftWords.IsSubsetOf(rightWords) || rightWords.IsSubsetOf(leftWords))
                {
                    return true;
                }
            }
            else if (left.Contains(right) || right.Contains(left))
            {
                return true;
            }

            Func<string, bool> isOriginalOrEnglish = n =>
            {
                var s = n.ToLowerInvariant();
                return s.Contains("original") || s.Contains("оригинал") || s.Contains("english") || s.Contains("английский") || s.Contains("eng") || s == "en";
            };

            if (isOriginalOrEnglish(left) && isOriginalOrEnglish(right))
            {
                return true;
            }

            return false;
        }
    }

    // MARK: - Mock Storage
    public class MockStorage
    {
        public Dictionary<string, string> SavedVoiceovers = new();
        public string? GlobalSavedVoiceover = null;

        public void SaveLastVoiceover(int kpId, string voiceover)
        {
            SavedVoiceovers[$"kp_{kpId}"] = voiceover;
            GlobalSavedVoiceover = voiceover;
        }

        public string? LoadLastVoiceover(int kpId)
        {
            if (SavedVoiceovers.TryGetValue($"kp_{kpId}", out var v)) return v;
            return null;
        }
    }

    // MARK: - PlayerViewModel State Machine (Mirroring PlayerView.swift)
    public class PlayerViewModel
    {
        public int? CurrentKpId { get; private set; }
        public int? CurrentSeason { get; private set; }
        public int? CurrentEpisode { get; private set; }
        public string? TargetVoiceover { get; private set; }
        public string? _currentTranslationName { get; private set; }
        public string? CurrentTranslationName => _currentTranslationName;
        public string? CurrentIframeUrl { get; private set; }
        public List<string> AvailableVoiceovers { get; private set; } = new();
        public double CurrentTime { get; set; } = 0;
        public bool IsLoading { get; private set; }
        public bool IsPlaying { get; private set; }
        public string? Error { get; private set; }

        public AllohaApiResult? SeriesResult { get; set; }
        public bool IsMovie => SeriesResult?.Movie != null;
        public MockStorage Storage { get; set; }

        public PlayerViewModel(MockStorage storage)
        {
            Storage = storage;
        }

        public void PersistVoiceoverSelection(string voiceover)
        {
            if (CurrentKpId != null && !string.IsNullOrEmpty(voiceover))
            {
                Storage.SaveLastVoiceover(CurrentKpId.Value, voiceover);
            }
        }

        // Swift lines 378–416
        public void BeginLoad(
            string? iframeUrl,
            int? kpId,
            int? season = null,
            int? episode = null,
            string? directStreamUrl = null,
            List<string>? voices = null,
            List<string>? subtitles = null,
            string? selectedVoiceover = null)
        {
            CurrentKpId = kpId;
            CurrentSeason = season;
            CurrentEpisode = episode;

            // Worker M1 V2 Fix:
            if (this.TargetVoiceover == null)
            {
                this.TargetVoiceover = selectedVoiceover;
            }
            this._currentTranslationName = selectedVoiceover;

            this.CurrentTime = 0;
            if (!string.IsNullOrEmpty(iframeUrl))
            {
                this.CurrentIframeUrl = iframeUrl;
            }

            if (SeriesResult != null && season != null && episode != null)
            {
                var seasonObj = SeriesResult.Seasons.FirstOrDefault(s => s.Season == season.Value);
                var epObj = seasonObj?.Episodes.FirstOrDefault(e => e.Episode == episode.Value);
                if (epObj != null)
                {
                    this.AvailableVoiceovers = epObj.Translations.Select(t => t.Name).ToList();
                }
            }
            else if (SeriesResult?.Movie != null)
            {
                this.AvailableVoiceovers = SeriesResult.Movie.Translations.Select(t => t.Name).ToList();
            }
            else if (voices != null && voices.Count > 0)
            {
                this.AvailableVoiceovers = new List<string>(voices);
            }

            // Persistence guard check:
            if (kpId != null && !string.IsNullOrEmpty(selectedVoiceover))
            {
                if (TargetVoiceover != null && AllohaMatching.AllohaTranslationNamesMatch(selectedVoiceover, TargetVoiceover))
                {
                    PersistVoiceoverSelection(selectedVoiceover);
                }
                else if (TargetVoiceover == null)
                {
                    PersistVoiceoverSelection(selectedVoiceover);
                }
            }

            IsLoading = true;
            IsPlaying = true;
        }

        // Swift lines 793–921
        public void SwitchVoiceover(string name, int? index = null)
        {
            double savedTime = this.CurrentTime;
            AllohaTranslation? targetTranslation = null;

            if (IsMovie)
            {
                if (SeriesResult?.Movie != null)
                {
                    var movie = SeriesResult.Movie;
                    if (index.HasValue && index.Value < movie.Translations.Count && AllohaMatching.AllohaTranslationNamesMatch(movie.Translations[index.Value].Name, name))
                    {
                        targetTranslation = movie.Translations[index.Value];
                    }
                    else
                    {
                        targetTranslation = movie.Translations.FirstOrDefault(t => AllohaMatching.AllohaTranslationNamesMatch(t.Name, name))
                                           ?? (index.HasValue && index.Value < movie.Translations.Count ? movie.Translations[index.Value] : null);
                    }
                }
            }
            else
            {
                if (SeriesResult != null && CurrentSeason.HasValue && CurrentEpisode.HasValue)
                {
                    var seasonObj = SeriesResult.Seasons.FirstOrDefault(s => s.Season == CurrentSeason.Value);
                    var epObj = seasonObj?.Episodes.FirstOrDefault(e => e.Episode == CurrentEpisode.Value);
                    if (epObj != null)
                    {
                        if (index.HasValue && index.Value < epObj.Translations.Count && AllohaMatching.AllohaTranslationNamesMatch(epObj.Translations[index.Value].Name, name))
                        {
                            targetTranslation = epObj.Translations[index.Value];
                        }
                        else
                        {
                            targetTranslation = epObj.Translations.FirstOrDefault(t => AllohaMatching.AllohaTranslationNamesMatch(t.Name, name))
                                               ?? (index.HasValue && index.Value < epObj.Translations.Count ? epObj.Translations[index.Value] : null);
                        }
                    }
                }
            }

            if (targetTranslation != null)
            {
                _currentTranslationName = targetTranslation.Name;
                TargetVoiceover = targetTranslation.Name;
                PersistVoiceoverSelection(targetTranslation.Name);

                CurrentIframeUrl = targetTranslation.IframeUrl;
                CurrentTime = savedTime; // Preserves position
                return;
            }

            // Fallback native track switch
            _currentTranslationName = name;
            TargetVoiceover = name;
            PersistVoiceoverSelection(name);
        }

        // Swift lines 1736–1773
        public void PlayEpisode(int season, int episode, AllohaTranslation translation)
        {
            _currentTranslationName = translation.Name;
            if (TargetVoiceover == null)
            {
                TargetVoiceover = translation.Name;
            }
            if (TargetVoiceover != null && AllohaMatching.AllohaTranslationNamesMatch(translation.Name, TargetVoiceover))
            {
                PersistVoiceoverSelection(translation.Name);
            }

            BeginLoad(
                iframeUrl: translation.IframeUrl,
                kpId: CurrentKpId,
                season: season,
                episode: episode,
                selectedVoiceover: translation.Name
            );
        }

        // Swift lines 1776–1799
        public (int season, int episode, AllohaTranslation translation)? NextEpisodeCandidate()
        {
            if (SeriesResult == null || !SeriesResult.IsSerial || !CurrentSeason.HasValue || !CurrentEpisode.HasValue)
                return null;

            var sortedSeasons = SeriesResult.Seasons.OrderBy(s => s.Season).ToList();
            bool foundCurrentEpisode = false;

            foreach (var season in sortedSeasons)
            {
                foreach (var episode in season.Episodes.OrderBy(e => e.Episode))
                {
                    if (foundCurrentEpisode)
                    {
                        var translation = PreferredTranslation(episode);
                        if (translation == null) return null;
                        return (season.Season, episode.Episode, translation);
                    }

                    if (season.Season == CurrentSeason.Value && episode.Episode == CurrentEpisode.Value)
                    {
                        foundCurrentEpisode = true;
                    }
                }
            }

            return null;
        }

        // Swift lines 1801–1822
        public (int season, int episode, AllohaTranslation translation)? PreviousEpisodeCandidate()
        {
            if (SeriesResult == null || !SeriesResult.IsSerial || !CurrentSeason.HasValue || !CurrentEpisode.HasValue)
                return null;

            var sortedSeasons = SeriesResult.Seasons.OrderBy(s => s.Season).ToList();
            (int season, int episode, AllohaTranslation translation)? lastSeen = null;

            foreach (var season in sortedSeasons)
            {
                foreach (var episode in season.Episodes.OrderBy(e => e.Episode))
                {
                    if (season.Season == CurrentSeason.Value && episode.Episode == CurrentEpisode.Value)
                    {
                        return lastSeen;
                    }
                    var translation = PreferredTranslation(episode);
                    if (translation != null)
                    {
                        lastSeen = (season.Season, episode.Episode, translation);
                    }
                }
            }

            return null;
        }

        // Swift lines 1824–1847
        public AllohaTranslation? PreferredTranslation(AllohaEpisode episode)
        {
            if (TargetVoiceover != null)
            {
                var match = episode.Translations.FirstOrDefault(t => AllohaMatching.AllohaTranslationNamesMatch(t.Name, TargetVoiceover));
                if (match != null) return match;
            }

            if (_currentTranslationName != null)
            {
                var match = episode.Translations.FirstOrDefault(t => AllohaMatching.AllohaTranslationNamesMatch(t.Name, _currentTranslationName));
                if (match != null) return match;
            }

            if (CurrentKpId.HasValue)
            {
                var saved = Storage.LoadLastVoiceover(CurrentKpId.Value);
                if (saved != null)
                {
                    var match = episode.Translations.FirstOrDefault(t => AllohaMatching.AllohaTranslationNamesMatch(t.Name, saved));
                    if (match != null) return match;
                }
            }

            if (Storage.GlobalSavedVoiceover != null)
            {
                var match = episode.Translations.FirstOrDefault(t => AllohaMatching.AllohaTranslationNamesMatch(t.Name, Storage.GlobalSavedVoiceover));
                if (match != null) return match;
            }

            return episode.Translations.FirstOrDefault();
        }

        public void PlayNextEpisode()
        {
            var next = NextEpisodeCandidate();
            if (next.HasValue)
            {
                PlayEpisode(next.Value.season, next.Value.episode, next.Value.translation);
            }
        }

        public void PlayPreviousEpisode()
        {
            var prev = PreviousEpisodeCandidate();
            if (prev.HasValue)
            {
                PlayEpisode(prev.Value.season, prev.Value.episode, prev.Value.translation);
            }
        }
    }

    class Program
    {
        static int totalTests = 0;
        static int passedTests = 0;

        static void Assert(bool condition, string testName, string details = "")
        {
            totalTests++;
            if (condition)
            {
                passedTests++;
                Console.WriteLine($"[PASS] {testName}");
            }
            else
            {
                Console.ForegroundColor = ConsoleColor.Red;
                Console.WriteLine($"[FAIL] {testName} - {details}");
                Console.ResetColor();
            }
        }

        static void Main(string[] args)
        {
            Console.WriteLine("==========================================================");
            Console.WriteLine(" EMPIRICAL VERIFICATION SUITE: STICKY VOICEOVER PREFERENCE");
            Console.WriteLine("==========================================================");

            Test_Scenario1_FallbackAndRecovery();
            Test_Scenario2_MultiHopFallbackAndRecovery();
            Test_Scenario3_ManualUserSwitchOnFallbackEpisode();
            Test_Scenario4_MoviePlaybackAndInPlayerSwitch();
            Test_Scenario5_InitialSeriesLoadWithAndWithoutPreference();
            Test_Scenario6_PreviousEpisodeNavigation();
            Test_Scenario7_FuzzyMatchingFidelity();
            Test_Scenario8_PersistenceIsolationDuringFallback();

            Console.WriteLine("==========================================================");
            Console.WriteLine($"RESULT: {passedTests}/{totalTests} tests passed.");
            Console.WriteLine("==========================================================");

            if (passedTests != totalTests)
            {
                Environment.Exit(1);
            }
        }

        static void Test_Scenario1_FallbackAndRecovery()
        {
            Console.WriteLine("\n--- Scenario 1: Ep 1 (Dubbed) -> Ep 2 (Fallback: LostFilm) -> Ep 3 (Restores: Dubbed) ---");
            var storage = new MockStorage();
            var vm = new PlayerViewModel(storage);

            var series = new AllohaApiResult
            {
                IsSerial = true,
                Seasons = new List<AllohaSeason>
                {
                    new AllohaSeason
                    {
                        Season = 1,
                        Episodes = new List<AllohaEpisode>
                        {
                            new AllohaEpisode
                            {
                                Episode = 1,
                                Translations = new List<AllohaTranslation>
                                {
                                    new AllohaTranslation("Дубляж", "https://iframe.alloha/s1e1_dub"),
                                    new AllohaTranslation("LostFilm", "https://iframe.alloha/s1e1_lost"),
                                    new AllohaTranslation("HDRezka", "https://iframe.alloha/s1e1_rezka")
                                }
                            },
                            new AllohaEpisode
                            {
                                Episode = 2,
                                Translations = new List<AllohaTranslation>
                                {
                                    new AllohaTranslation("LostFilm", "https://iframe.alloha/s1e2_lost"),
                                    new AllohaTranslation("HDRezka", "https://iframe.alloha/s1e2_rezka")
                                }
                            },
                            new AllohaEpisode
                            {
                                Episode = 3,
                                Translations = new List<AllohaTranslation>
                                {
                                    new AllohaTranslation("LostFilm", "https://iframe.alloha/s1e3_lost"),
                                    new AllohaTranslation("HDRezka", "https://iframe.alloha/s1e3_rezka"),
                                    new AllohaTranslation("Дубляж", "https://iframe.alloha/s1e3_dub")
                                }
                            }
                        }
                    }
                }
            };
            vm.SeriesResult = series;

            // Start Episode 1 with Дубляж
            vm.BeginLoad(
                iframeUrl: "https://iframe.alloha/s1e1_dub",
                kpId: 404,
                season: 1,
                episode: 1,
                selectedVoiceover: "Дубляж"
            );

            Assert(vm.TargetVoiceover == "Дубляж", "S1E1: TargetVoiceover initialized to Дубляж");
            Assert(vm.CurrentTranslationName == "Дубляж", "S1E1: CurrentTranslationName is Дубляж");
            Assert(storage.LoadLastVoiceover(404) == "Дубляж", "S1E1: Persisted voiceover is Дубляж");

            // Advance to Episode 2 (only LostFilm and HDRezka available)
            var candidateE2 = vm.NextEpisodeCandidate();
            Assert(candidateE2.HasValue, "S1E2 candidate found");
            Assert(candidateE2.HasValue && candidateE2.Value.translation.Name == "LostFilm", "S1E2 selected fallback translation: LostFilm");

            vm.PlayNextEpisode();

            Assert(vm.CurrentSeason == 1 && vm.CurrentEpisode == 2, "S1E2: Now on Season 1 Episode 2");
            Assert(vm.CurrentTranslationName == "LostFilm", "S1E2: UI CurrentTranslationName displays active fallback LostFilm");
            Assert(vm.TargetVoiceover == "Дубляж", "S1E2: TargetVoiceover PRESERVED as Дубляж (not overwritten by LostFilm)");
            Assert(storage.LoadLastVoiceover(404) == "Дубляж", "S1E2: Storage STILL preserves user preference Дубляж");

            // Advance to Episode 3 (Dubbed is back!)
            var candidateE3 = vm.NextEpisodeCandidate();
            Assert(candidateE3.HasValue, "S1E3 candidate found");
            Assert(candidateE3.HasValue && candidateE3.Value.translation.Name == "Дубляж", "S1E3 candidate automatically recovered preferred Дубляж");

            vm.PlayNextEpisode();

            Assert(vm.CurrentSeason == 1 && vm.CurrentEpisode == 3, "S1E3: Now on Season 1 Episode 3");
            Assert(vm.CurrentTranslationName == "Дубляж", "S1E3: UI CurrentTranslationName restored to Дубляж");
            Assert(vm.TargetVoiceover == "Дубляж", "S1E3: TargetVoiceover remains Дубляж");
            Assert(storage.LoadLastVoiceover(404) == "Дубляж", "S1E3: Storage maintains Дубляж");
        }

        static void Test_Scenario2_MultiHopFallbackAndRecovery()
        {
            Console.WriteLine("\n--- Scenario 2: Multi-hop Fallback (Ep 1: Dub -> Ep 2: Lost -> Ep 3: Rezka -> Ep 4: Dub) ---");
            var storage = new MockStorage();
            var vm = new PlayerViewModel(storage);

            var series = new AllohaApiResult
            {
                IsSerial = true,
                Seasons = new List<AllohaSeason>
                {
                    new AllohaSeason
                    {
                        Season = 1,
                        Episodes = new List<AllohaEpisode>
                        {
                            new AllohaEpisode { Episode = 1, Translations = new() { new("Дубляж", "url1"), new("LostFilm", "url2") } },
                            new AllohaEpisode { Episode = 2, Translations = new() { new("LostFilm", "url3") } },
                            new AllohaEpisode { Episode = 3, Translations = new() { new("HDRezka", "url4") } },
                            new AllohaEpisode { Episode = 4, Translations = new() { new("LostFilm", "url5"), new("HDRezka", "url6"), new("Дубляж", "url7") } },
                        }
                    }
                }
            };
            vm.SeriesResult = series;

            vm.BeginLoad("url1", 505, 1, 1, selectedVoiceover: "Дубляж");

            // Advance to Ep 2
            vm.PlayNextEpisode();
            Assert(vm.CurrentEpisode == 2 && vm.CurrentTranslationName == "LostFilm" && vm.TargetVoiceover == "Дубляж",
                   "Ep 2: Playing LostFilm while TargetVoiceover == Дубляж");

            // Advance to Ep 3
            vm.PlayNextEpisode();
            Assert(vm.CurrentEpisode == 3 && vm.CurrentTranslationName == "HDRezka" && vm.TargetVoiceover == "Дубляж",
                   "Ep 3: Playing HDRezka while TargetVoiceover == Дубляж");

            // Advance to Ep 4
            vm.PlayNextEpisode();
            Assert(vm.CurrentEpisode == 4 && vm.CurrentTranslationName == "Дубляж" && vm.TargetVoiceover == "Дубляж",
                   "Ep 4: Multi-hop recovery restores Дубляж successfully!");
        }

        static void Test_Scenario3_ManualUserSwitchOnFallbackEpisode()
        {
            Console.WriteLine("\n--- Scenario 3: Manual Switch on Fallback Episode overrides TargetVoiceover ---");
            var storage = new MockStorage();
            var vm = new PlayerViewModel(storage);

            var series = new AllohaApiResult
            {
                IsSerial = true,
                Seasons = new List<AllohaSeason>
                {
                    new AllohaSeason
                    {
                        Season = 1,
                        Episodes = new List<AllohaEpisode>
                        {
                            new AllohaEpisode { Episode = 1, Translations = new() { new("Дубляж", "url1"), new("LostFilm", "url2") } },
                            new AllohaEpisode { Episode = 2, Translations = new() { new("LostFilm", "url3"), new("HDRezka", "url4") } },
                            new AllohaEpisode { Episode = 3, Translations = new() { new("Дубляж", "url5"), new("HDRezka", "url6"), new("LostFilm", "url7") } },
                        }
                    }
                }
            };
            vm.SeriesResult = series;

            vm.BeginLoad("url1", 606, 1, 1, selectedVoiceover: "Дубляж");
            vm.PlayNextEpisode(); // Advances to Ep 2 (LostFilm fallback)

            Assert(vm.CurrentTranslationName == "LostFilm" && vm.TargetVoiceover == "Дубляж", "Ep 2 playing LostFilm fallback");

            // User explicitly opens VoiceoverPickerSheet and chooses HDRezka
            vm.CurrentTime = 120.5;
            vm.SwitchVoiceover("HDRezka");

            Assert(vm.CurrentTranslationName == "HDRezka", "Ep 2: Manual switch updated CurrentTranslationName to HDRezka");
            Assert(vm.TargetVoiceover == "HDRezka", "Ep 2: Manual switch updated TargetVoiceover to HDRezka");
            Assert(storage.LoadLastVoiceover(606) == "HDRezka", "Ep 2: Manual switch persisted HDRezka to storage");
            Assert(vm.CurrentTime == 120.5, "Ep 2: Manual switch preserved playback position");

            // Now advance to Ep 3. Ep 3 has Дубляж, HDRezka, LostFilm.
            // It MUST pick HDRezka (the user's latest deliberate choice), NOT Дубляж!
            vm.PlayNextEpisode();

            Assert(vm.CurrentEpisode == 3, "Now on Ep 3");
            Assert(vm.CurrentTranslationName == "HDRezka", "Ep 3: Respects updated user choice (HDRezka), did not revert to old Дубляж");
            Assert(vm.TargetVoiceover == "HDRezka", "Ep 3: TargetVoiceover remains HDRezka");
        }

        static void Test_Scenario4_MoviePlaybackAndInPlayerSwitch()
        {
            Console.WriteLine("\n--- Scenario 4: Movie Playback & In-Player Voiceover Switch ---");
            var storage = new MockStorage();
            var vm = new PlayerViewModel(storage);

            var movieResult = new AllohaApiResult
            {
                IsSerial = false,
                Movie = new AllohaMovie
                {
                    Translations = new List<AllohaTranslation>
                    {
                        new AllohaTranslation("Дублированный", "https://iframe/movie_dub"),
                        new AllohaTranslation("LostFilm", "https://iframe/movie_lost"),
                        new AllohaTranslation("Оригинал (Eng)", "https://iframe/movie_orig")
                    }
                }
            };
            vm.SeriesResult = movieResult;

            vm.BeginLoad("https://iframe/movie_dub", 707, selectedVoiceover: "Дублированный");

            Assert(vm.AvailableVoiceovers.Count == 3, "Movie has 3 available voiceovers");
            Assert(vm.TargetVoiceover == "Дублированный", "Movie TargetVoiceover is Дублированный");
            Assert(vm.CurrentTranslationName == "Дублированный", "Movie CurrentTranslationName is Дублированный");
            Assert(storage.LoadLastVoiceover(707) == "Дублированный", "Movie persisted selection");

            // User switches to Original at 45.0 seconds
            vm.CurrentTime = 45.0;
            vm.SwitchVoiceover("Оригинал (Eng)");

            Assert(vm.CurrentTranslationName == "Оригинал (Eng)", "Movie switched to Оригинал (Eng)");
            Assert(vm.TargetVoiceover == "Оригинал (Eng)", "Movie TargetVoiceover updated to Оригинал (Eng)");
            Assert(vm.CurrentIframeUrl == "https://iframe/movie_orig", "Movie iframeUrl updated");
            Assert(storage.LoadLastVoiceover(707) == "Оригинал (Eng)", "Movie persisted new selection to storage");
            Assert(vm.CurrentTime == 45.0, "Movie preserved playback position across switch");
        }

        static void Test_Scenario5_InitialSeriesLoadWithAndWithoutPreference()
        {
            Console.WriteLine("\n--- Scenario 5: Initial Series Load ---");
            var storage = new MockStorage();
            var vm = new PlayerViewModel(storage);

            var series = new AllohaApiResult
            {
                IsSerial = true,
                Seasons = new List<AllohaSeason>
                {
                    new AllohaSeason
                    {
                        Season = 1,
                        Episodes = new List<AllohaEpisode>
                        {
                            new AllohaEpisode { Episode = 1, Translations = new() { new("Дубляж", "url1"), new("LostFilm", "url2") } },
                            new AllohaEpisode { Episode = 2, Translations = new() { new("LostFilm", "url3") } }
                        }
                    }
                }
            };
            vm.SeriesResult = series;

            // Load with null selectedVoiceover
            vm.BeginLoad("url1", 808, 1, 1, selectedVoiceover: null);
            Assert(vm.TargetVoiceover == null, "Initial load with null selectedVoiceover leaves TargetVoiceover null");
            Assert(vm.CurrentTranslationName == null, "Initial load with null selectedVoiceover leaves CurrentTranslationName null");

            // When PlayEpisode is called for Ep 1 with Дубляж
            vm.PlayEpisode(1, 1, series.Seasons[0].Episodes[0].Translations[0]);
            Assert(vm.TargetVoiceover == "Дубляж", "PlayEpisode initializes TargetVoiceover to Дубляж");
            Assert(vm.CurrentTranslationName == "Дубляж", "PlayEpisode sets CurrentTranslationName to Дубляж");
            Assert(storage.LoadLastVoiceover(808) == "Дубляж", "PlayEpisode persists Дубляж");
        }

        static void Test_Scenario6_PreviousEpisodeNavigation()
        {
            Console.WriteLine("\n--- Scenario 6: Previous Episode Navigation ---");
            var storage = new MockStorage();
            var vm = new PlayerViewModel(storage);

            var series = new AllohaApiResult
            {
                IsSerial = true,
                Seasons = new List<AllohaSeason>
                {
                    new AllohaSeason
                    {
                        Season = 1,
                        Episodes = new List<AllohaEpisode>
                        {
                            new AllohaEpisode { Episode = 1, Translations = new() { new("Дубляж", "url1"), new("LostFilm", "url2") } },
                            new AllohaEpisode { Episode = 2, Translations = new() { new("LostFilm", "url3") } },
                            new AllohaEpisode { Episode = 3, Translations = new() { new("Дубляж", "url4"), new("LostFilm", "url5") } }
                        }
                    }
                }
            };
            vm.SeriesResult = series;

            // Start on Ep 3 with Дубляж
            vm.BeginLoad("url4", 909, 1, 3, selectedVoiceover: "Дубляж");

            // Navigate back to Ep 2 (only LostFilm)
            var prevCandidate = vm.PreviousEpisodeCandidate();
            Assert(prevCandidate.HasValue, "Previous candidate for Ep 3 exists");
            Assert(prevCandidate.HasValue && prevCandidate.Value.episode == 2 && prevCandidate.Value.translation.Name == "LostFilm",
                   "Previous candidate is Ep 2 with fallback LostFilm");

            vm.PlayPreviousEpisode();
            Assert(vm.CurrentEpisode == 2 && vm.CurrentTranslationName == "LostFilm" && vm.TargetVoiceover == "Дубляж",
                   "Playing Ep 2 with fallback LostFilm, TargetVoiceover preserved as Дубляж");

            // Navigate back to Ep 1 (has Дубляж)
            var prevCandidate2 = vm.PreviousEpisodeCandidate();
            Assert(prevCandidate2.HasValue, "Previous candidate for Ep 2 exists");
            Assert(prevCandidate2.HasValue && prevCandidate2.Value.episode == 1 && prevCandidate2.Value.translation.Name == "Дубляж",
                   "Previous candidate is Ep 1 restoring Дубляж");

            vm.PlayPreviousEpisode();
            Assert(vm.CurrentEpisode == 1 && vm.CurrentTranslationName == "Дубляж" && vm.TargetVoiceover == "Дубляж",
                   "Playing Ep 1 with restored Дубляж");
        }

        static void Test_Scenario7_FuzzyMatchingFidelity()
        {
            Console.WriteLine("\n--- Scenario 7: Fuzzy & Normalized Matching in AllohaMatching ---");
            Assert(AllohaMatching.AllohaTranslationNamesMatch("Дублированный [Чистый звук]", "Дублированный"), "Дублированный [Чистый звук] matches Дублированный");
            Assert(AllohaMatching.AllohaTranslationNamesMatch("DUB", "Дубляж"), "DUB matches Дубляж");
            Assert(AllohaMatching.AllohaTranslationNamesMatch("AlexFilm", "AlexFilm Studio"), "AlexFilm variants match");
            Assert(AllohaMatching.AllohaTranslationNamesMatch("Оригинал (Eng)", "English"), "Original / English matches");
            Assert(!AllohaMatching.AllohaTranslationNamesMatch("LostFilm", "HDRezka"), "LostFilm does NOT match HDRezka");
            Assert(!AllohaMatching.AllohaTranslationNamesMatch("Дубляж", "Кубик в кубе"), "Дубляж does NOT match Кубик в кубе");
        }

        static void Test_Scenario8_PersistenceIsolationDuringFallback()
        {
            Console.WriteLine("\n--- Scenario 8: Persistence Isolation During Fallback ---");
            var storage = new MockStorage();
            var vm = new PlayerViewModel(storage);

            var series = new AllohaApiResult
            {
                IsSerial = true,
                Seasons = new List<AllohaSeason>
                {
                    new AllohaSeason
                    {
                        Season = 1,
                        Episodes = new List<AllohaEpisode>
                        {
                            new AllohaEpisode { Episode = 1, Translations = new() { new("Дубляж", "url1") } },
                            new AllohaEpisode { Episode = 2, Translations = new() { new("LostFilm", "url2") } },
                        }
                    }
                }
            };
            vm.SeriesResult = series;

            vm.BeginLoad("url1", 1010, 1, 1, selectedVoiceover: "Дубляж");
            Assert(storage.LoadLastVoiceover(1010) == "Дубляж", "Initial persist is Дубляж");

            // Ep 2 fallback
            vm.PlayNextEpisode();
            Assert(vm.CurrentTranslationName == "LostFilm", "Ep 2 playing LostFilm");
            Assert(storage.LoadLastVoiceover(1010) == "Дубляж", "Storage was NOT contaminated with fallback LostFilm");
        }
    }
}
