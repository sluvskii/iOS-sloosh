$code = @"
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;

public class AllohaTranslation {
    public string Id { get; set; }
    public string Name { get; set; }
    public string IframeUrl { get; set; }
    public string StreamUrl { get; set; }
    public AllohaTranslation() {}
    public AllohaTranslation(string id, string name, string iframeUrl, string streamUrl = null) {
        Id = id;
        Name = name;
        IframeUrl = iframeUrl;
        StreamUrl = streamUrl;
    }
}

public class AllohaEpisode {
    public int Season { get; set; }
    public int Episode { get; set; }
    public List<AllohaTranslation> Translations { get; set; }
    public AllohaEpisode() { Translations = new List<AllohaTranslation>(); }
    public AllohaEpisode(int s, int e, List<AllohaTranslation> t) {
        Season = s;
        Episode = e;
        Translations = t;
    }
}

public class AllohaSeason {
    public int Season { get; set; }
    public List<AllohaEpisode> Episodes { get; set; }
    public AllohaSeason() { Episodes = new List<AllohaEpisode>(); }
    public AllohaSeason(int s, List<AllohaEpisode> ep) {
        Season = s;
        Episodes = ep;
    }
}

public class AllohaMovie {
    public string Title { get; set; }
    public string IframeUrl { get; set; }
    public List<AllohaTranslation> Translations { get; set; }
    public AllohaMovie() { Translations = new List<AllohaTranslation>(); }
    public AllohaMovie(string t, string u, List<AllohaTranslation> tr) {
        Title = t;
        IframeUrl = u;
        Translations = tr;
    }
}

public class AllohaApiResult {
    public string Title { get; set; }
    public bool IsSerial { get; set; }
    public AllohaMovie Movie { get; set; }
    public List<AllohaSeason> Seasons { get; set; }
    public AllohaApiResult() { Seasons = new List<AllohaSeason>(); }
}

public static class AllohaHelper {
    public static string NormalizedAllohaTranslationName(string raw) {
        if (string.IsNullOrWhiteSpace(raw)) return "";
        string val = raw.Trim();
        val = val.Replace("(Russian)", "")
                 .Replace("AC3 51 @ 640 kbps - Blu-ray CEE", "")
                 .Replace("AC3 5.1 @ 640 kbps", "")
                 .Replace("DUB", "\u0414\u0443\u0431\u043B\u044F\u0436")
                 .Replace("MVO", "\u041C\u043D\u043E\u0433\u043E\u0433\u043E\u043B\u043E\u0441\u044B\u0439")
                 .Replace("DVO", "\u0414\u0432\u0443\u0445\u0433\u043E\u043B\u043E\u0441\u044B\u0439")
                 .Replace("AVO", "\u0410\u0432\u0442\u043E\u0440\u0441\u043A\u0438\u0439")
                 .Replace("\u041F\u041C", "\u041F\u0440\u043E\u0444. \u043C\u043D\u043E\u0433\u043E\u0433\u043E\u043B\u043E\u0441\u044B\u0439")
                 .Replace("\u041F\u0414", "\u041F\u0440\u043E\u0444. \u0434\u0432\u0443\u0445\u0433\u043E\u043B\u043E\u0441\u044B\u0439")
                 .Replace("\u041B\u041C", "\u041B\u044E\u0431. \u043C\u043D\u043E\u0433\u043E\u0433\u043E\u043B\u043E\u0441\u044B\u0439")
                 .Replace("\u041B\u0414", "\u041B\u044E\u0431. \u0434\u0432\u0443\u0445\u0433\u043E\u043B\u043E\u0441\u044B\u0439")
                 .Replace("[", " ").Replace("]", " ")
                 .Replace("(", " ").Replace(")", " ")
                 .Replace("|", " ").Trim();
        
        while (val.StartsWith("-") || val.StartsWith(",")) val = val.Substring(1).Trim();
        while (val.EndsWith("-") || val.EndsWith(",")) val = val.Substring(0, val.Length - 1).Trim();
        val = Regex.Replace(val, @"\s+", " ").Trim();
        return val;
    }

    public static bool AllohaTranslationNamesMatch(string lhs, string rhs, bool exactOnly = false) {
        string left = NormalizedAllohaTranslationName(lhs).ToLower();
        string right = NormalizedAllohaTranslationName(rhs).ToLower();
        if (string.IsNullOrEmpty(left) || string.IsNullOrEmpty(right)) return false;
        if (left == right) return true;

        var leftWords = new HashSet<string>(Regex.Split(left, @"[^a-zA-Z0-9\u0400-\u04FF]+").Where(w => w.Length > 2));
        var rightWords = new HashSet<string>(Regex.Split(right, @"[^a-zA-Z0-9\u0400-\u04FF]+").Where(w => w.Length > 2));

        if (leftWords.Count > 0 && rightWords.Count > 0) {
            if (leftWords.SetEquals(rightWords) || leftWords.IsSubsetOf(rightWords) || rightWords.IsSubsetOf(leftWords)) {
                return true;
            }
        } else if (left.Contains(right) || right.Contains(left)) {
            return true;
        }

        Func<string, bool> isOriginalOrEnglish = delegate(string name) {
            string n = name.ToLower();
            return n.Contains("original") || n.Contains("\u043E\u0440\u0438\u0433\u0438\u043D\u0430\u043B") || n.Contains("english") || n.Contains("\u0430\u043D\u0433\u043B\u0438\u0439\u0441\u043A\u0438\u0439") || n.Contains("eng") || n == "en";
        };

        if (isOriginalOrEnglish(left) && isOriginalOrEnglish(right)) return true;
        return false;
    }
}

public class MockProgressStore {
    public static Dictionary<int, string> LastVoiceovers = new Dictionary<int, string>();
    public static void SaveLastVoiceover(int kpId, string voice) {
        LastVoiceovers[kpId] = voice;
    }
    public static string LoadLastVoiceover(int kpId) {
        string res;
        if (LastVoiceovers.TryGetValue(kpId, out res)) return res;
        return null;
    }
}

public class PlayerViewModelSim {
    public int? CurrentKpId;
    public int? CurrentSeason;
    public int? CurrentEpisode;
    public string TargetVoiceover;
    public string _currentTranslationName;
    public string CurrentTranslationName { get { return _currentTranslationName; } }
    public List<string> AvailableVoiceovers = new List<string>();
    public AllohaApiResult SeriesResult;
    public double CurrentTime = 0;
    public string CurrentIframeUrl;
    public bool IsMovie {
        get { return SeriesResult != null && (!SeriesResult.IsSerial || SeriesResult.Movie != null); }
    }

    public void Load(string iframeUrl, int? kpId, int? season, int? episode, string selectedVoiceover) {
        TargetVoiceover = selectedVoiceover;
        BeginLoad(iframeUrl, kpId, season, episode, selectedVoiceover, true);
    }

    public void BeginLoad(string iframeUrl, int? kpId, int? season, int? episode, string selectedVoiceover, bool updateTargetVoiceover = false) {
        CurrentKpId = kpId;
        CurrentSeason = season;
        CurrentEpisode = episode;
        if (updateTargetVoiceover || TargetVoiceover == null) {
            TargetVoiceover = selectedVoiceover;
        }
        _currentTranslationName = selectedVoiceover;
        CurrentTime = 0;
        CurrentIframeUrl = iframeUrl;

        if (SeriesResult != null && season.HasValue && episode.HasValue) {
            var sObj = SeriesResult.Seasons.FirstOrDefault(s => s.Season == season.Value);
            var epObj = sObj != null ? sObj.Episodes.FirstOrDefault(e => e.Episode == episode.Value) : null;
            if (epObj != null) {
                AvailableVoiceovers = epObj.Translations.Select(t => t.Name).ToList();
            }
        } else if (SeriesResult != null && SeriesResult.Movie != null) {
            AvailableVoiceovers = SeriesResult.Movie.Translations.Select(t => t.Name).ToList();
        }

        if (kpId.HasValue && !string.IsNullOrEmpty(selectedVoiceover) && updateTargetVoiceover) {
            MockProgressStore.SaveLastVoiceover(kpId.Value, selectedVoiceover);
        }
    }

    public void SwitchVoiceover(string name, int? index = null) {
        double savedTime = CurrentTime;
        AllohaTranslation targetTranslation = null;

        if (IsMovie) {
            if (SeriesResult != null && SeriesResult.Movie != null) {
                var movie = SeriesResult.Movie;
                if (index.HasValue && index.Value < movie.Translations.Count && AllohaHelper.AllohaTranslationNamesMatch(movie.Translations[index.Value].Name, name)) {
                    targetTranslation = movie.Translations[index.Value];
                } else {
                    targetTranslation = movie.Translations.FirstOrDefault(t => AllohaHelper.AllohaTranslationNamesMatch(t.Name, name));
                    if (targetTranslation == null && index.HasValue && index.Value < movie.Translations.Count) {
                        targetTranslation = movie.Translations[index.Value];
                    }
                }
            }
        } else {
            if (SeriesResult != null && CurrentSeason.HasValue && CurrentEpisode.HasValue) {
                var sObj = SeriesResult.Seasons.FirstOrDefault(s => s.Season == CurrentSeason.Value);
                var epObj = sObj != null ? sObj.Episodes.FirstOrDefault(e => e.Episode == CurrentEpisode.Value) : null;
                if (epObj != null) {
                    if (index.HasValue && index.Value < epObj.Translations.Count && AllohaHelper.AllohaTranslationNamesMatch(epObj.Translations[index.Value].Name, name)) {
                        targetTranslation = epObj.Translations[index.Value];
                    } else {
                        targetTranslation = epObj.Translations.FirstOrDefault(t => AllohaHelper.AllohaTranslationNamesMatch(t.Name, name));
                        if (targetTranslation == null && index.HasValue && index.Value < epObj.Translations.Count) {
                            targetTranslation = epObj.Translations[index.Value];
                        }
                    }
                }
            }
        }

        if (targetTranslation != null) {
            _currentTranslationName = targetTranslation.Name;
            TargetVoiceover = targetTranslation.Name;
            if (CurrentKpId.HasValue) MockProgressStore.SaveLastVoiceover(CurrentKpId.Value, targetTranslation.Name);
            CurrentIframeUrl = targetTranslation.IframeUrl;
            // Restore playback position
            CurrentTime = savedTime;
            return;
        }

        // Native audio track fallback
        _currentTranslationName = name;
        TargetVoiceover = name;
        if (CurrentKpId.HasValue) MockProgressStore.SaveLastVoiceover(CurrentKpId.Value, name);
    }

    public AllohaTranslation PreferredTranslation(AllohaEpisode episode) {
        if (!string.IsNullOrEmpty(TargetVoiceover)) {
            var match = episode.Translations.FirstOrDefault(t => AllohaHelper.AllohaTranslationNamesMatch(t.Name, TargetVoiceover));
            if (match != null) return match;
        }

        if (!string.IsNullOrEmpty(_currentTranslationName)) {
            var match = episode.Translations.FirstOrDefault(t => AllohaHelper.AllohaTranslationNamesMatch(t.Name, _currentTranslationName));
            if (match != null) return match;
        }

        if (CurrentKpId.HasValue) {
            var saved = MockProgressStore.LoadLastVoiceover(CurrentKpId.Value);
            if (!string.IsNullOrEmpty(saved)) {
                var match = episode.Translations.FirstOrDefault(t => AllohaHelper.AllohaTranslationNamesMatch(t.Name, saved));
                if (match != null) return match;
            }
        }

        return episode.Translations.FirstOrDefault();
    }

    public Tuple<int, int, AllohaTranslation> NextEpisodeCandidate() {
        if (SeriesResult == null || !SeriesResult.IsSerial || !CurrentSeason.HasValue || !CurrentEpisode.HasValue) return null;
        var sortedSeasons = SeriesResult.Seasons.OrderBy(s => s.Season).ToList();
        bool foundCurrent = false;

        foreach (var s in sortedSeasons) {
            foreach (var ep in s.Episodes.OrderBy(e => e.Episode)) {
                if (foundCurrent) {
                    var t = PreferredTranslation(ep);
                    if (t == null) return null;
                    return Tuple.Create(s.Season, ep.Episode, t);
                }
                if (s.Season == CurrentSeason.Value && ep.Episode == CurrentEpisode.Value) {
                    foundCurrent = true;
                }
            }
        }
        return null;
    }

    public void PlayEpisode(Tuple<int, int, AllohaTranslation> ep) {
        _currentTranslationName = ep.Item3.Name;
        if (TargetVoiceover == null) {
            TargetVoiceover = ep.Item3.Name;
        }
        if (TargetVoiceover != null && AllohaHelper.AllohaTranslationNamesMatch(ep.Item3.Name, TargetVoiceover)) {
            MockProgressStore.SaveLastVoiceover(CurrentKpId ?? 0, ep.Item3.Name);
        }

        BeginLoad(ep.Item3.IframeUrl, CurrentKpId, ep.Item1, ep.Item2, ep.Item3.Name, false);
    }
}

public class TestRunner {
    public static void RunAllTests() {
        Console.WriteLine("=== RUNNING FIXED SIMULATION TEST SUITE ===");

        // Test 4: Series Episode Transition
        var ep1Trans = new List<AllohaTranslation>();
        ep1Trans.Add(new AllohaTranslation("1", "\u0414\u0443\u0431\u043B\u044F\u0436", "https://stream.alloha.tv/s1e1_dub"));
        ep1Trans.Add(new AllohaTranslation("2", "LostFilm", "https://stream.alloha.tv/s1e1_lost"));
        ep1Trans.Add(new AllohaTranslation("3", "HDRezka", "https://stream.alloha.tv/s1e1_rezka"));
        var ep1 = new AllohaEpisode(1, 1, ep1Trans);

        var ep2Trans = new List<AllohaTranslation>();
        ep2Trans.Add(new AllohaTranslation("2", "LostFilm", "https://stream.alloha.tv/s1e2_lost"));
        var ep2 = new AllohaEpisode(1, 2, ep2Trans);

        var ep3Trans = new List<AllohaTranslation>();
        ep3Trans.Add(new AllohaTranslation("1", "\u0414\u0443\u0431\u043B\u044F\u0436", "https://stream.alloha.tv/s1e3_dub"));
        ep3Trans.Add(new AllohaTranslation("2", "LostFilm", "https://stream.alloha.tv/s1e3_lost"));
        ep3Trans.Add(new AllohaTranslation("3", "HDRezka", "https://stream.alloha.tv/s1e3_rezka"));
        var ep3 = new AllohaEpisode(1, 3, ep3Trans);

        var episodes = new List<AllohaEpisode>() { ep1, ep2, ep3 };
        var season1 = new AllohaSeason(1, episodes);
        var seasons = new List<AllohaSeason>() { season1 };

        var seriesResult = new AllohaApiResult();
        seriesResult.Title = "\u041B\u043E\u043A\u0438";
        seriesResult.IsSerial = true;
        seriesResult.Seasons = seasons;

        var vmSeries = new PlayerViewModelSim();
        vmSeries.SeriesResult = seriesResult;
        vmSeries.Load("https://stream.alloha.tv/s1e1_dub", 999999, 1, 1, "\u0414\u0443\u0431\u043B\u044F\u0436");

        Console.WriteLine("Started Series Ep 1 with translation: " + vmSeries.CurrentTranslationName + ", TargetVoiceover: " + vmSeries.TargetVoiceover);

        // Transition to Ep 2
        var cand2 = vmSeries.NextEpisodeCandidate();
        Console.WriteLine("Candidate for Ep 2: S" + cand2.Item1 + "E" + cand2.Item2 + " - " + cand2.Item3.Name);
        vmSeries.PlayEpisode(cand2);
        Console.WriteLine("Now playing Ep 2 with translation: " + vmSeries.CurrentTranslationName + ", TargetVoiceover: " + vmSeries.TargetVoiceover);

        if (vmSeries.CurrentTranslationName == "LostFilm" && vmSeries.TargetVoiceover == "\u0414\u0443\u0431\u043B\u044F\u0436") {
            Console.WriteLine("[PASS] Ep 2 plays fallback LostFilm while preserving TargetVoiceover=Дубляж");
        } else {
            Console.WriteLine("[FAIL] Ep 2 failed state check!");
        }

        // Transition to Ep 3
        var cand3 = vmSeries.NextEpisodeCandidate();
        Console.WriteLine("Candidate for Ep 3: S" + cand3.Item1 + "E" + cand3.Item2 + " - " + cand3.Item3.Name);
        vmSeries.PlayEpisode(cand3);
        Console.WriteLine("Now playing Ep 3 with translation: " + vmSeries.CurrentTranslationName + ", TargetVoiceover: " + vmSeries.TargetVoiceover);

        if (vmSeries.CurrentTranslationName == "\u0414\u0443\u0431\u043B\u044F\u0436" && vmSeries.TargetVoiceover == "\u0414\u0443\u0431\u043B\u044F\u0436") {
            Console.WriteLine("[PASS] Ep 3 restored user preference (Дубляж) successfully!");
        } else {
            Console.WriteLine("[FAIL] Ep 3 failed to restore Дубляж!");
        }

        Console.WriteLine("=== FIXED TEST COMPLETE ===");
    }
}
"@

Add-Type -TypeDefinition $code -Language CSharp
[TestRunner]::RunAllTests()
