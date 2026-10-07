use std::collections::HashSet;

use serde::Serialize;

/// Tokens in the "Possibly relevant memories..." line that precedes injected hits.
pub const CONTEXT_HEADER_TOKENS: f64 = 20.0;

/// Nearest-rank percentile of an ascending-sorted slice; `p` in 0..=100.
pub fn percentile(sorted: &[f64], p: f64) -> f64 {
    if sorted.is_empty() {
        return 0.0;
    }
    let n = sorted.len();
    let rank = ((p / 100.0) * n as f64).ceil() as usize;
    let index = rank.clamp(1, n).saturating_sub(1);
    sorted.get(index).copied().unwrap_or(0.0)
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Summary {
    pub n: usize,
    pub mean: f64,
    pub min: f64,
    pub p50: f64,
    pub p95: f64,
    pub p99: f64,
    pub max: f64,
}

pub fn summarise(values: &[f64]) -> Option<Summary> {
    if values.is_empty() {
        return None;
    }
    let mut sorted = values.to_vec();
    sorted.sort_by(f64::total_cmp);
    Some(Summary {
        n: sorted.len(),
        mean: sorted.iter().sum::<f64>() / sorted.len() as f64,
        min: percentile(&sorted, 0.0),
        p50: percentile(&sorted, 50.0),
        p95: percentile(&sorted, 95.0),
        p99: percentile(&sorted, 99.0),
        max: percentile(&sorted, 100.0),
    })
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    /// A prompt a memory should answer.
    Relevant,
    /// A prompt unrelated to anything in memory.
    Offtopic,
    /// A prompt in a memory-adjacent area that no memory answers.
    Adjacent,
}

/// One prompt with every memory scored against it, best first.
#[derive(Debug, Clone)]
pub struct Case {
    pub kind: Kind,
    pub expect: HashSet<String>,
    pub scored: Vec<(String, f64)>,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct GateRow {
    pub threshold: f64,
    /// Relevant prompts whose injected set holds an expected memory.
    pub recall: f64,
    /// Relevant prompts whose first injected memory is an expected one.
    pub top1_correct: f64,
    pub false_injection_offtopic: f64,
    pub false_injection_adjacent: f64,
    /// Correct injections over all injections; `None` when nothing was injected.
    pub precision: Option<f64>,
    pub mean_injected: f64,
    /// Mean tokens injected per prompt, header included when anything is injected.
    pub mean_tokens: f64,
}

pub fn gate_row(
    cases: &[Case],
    threshold: f64,
    top: usize,
    tokens_of: &dyn Fn(&str) -> f64,
) -> GateRow {
    let ratio = |part: f64, whole: f64| if whole == 0.0 { 0.0 } else { part / whole };

    let (mut relevant, mut offtopic, mut adjacent) = (0.0, 0.0, 0.0);
    let (mut recalled, mut top1, mut inj_off, mut inj_adj) = (0.0, 0.0, 0.0, 0.0);
    let (mut injections, mut correct) = (0.0, 0.0);
    let (mut injected_total, mut token_total) = (0.0, 0.0);

    for case in cases {
        let injected: Vec<&str> = case
            .scored
            .iter()
            .filter(|(_, score)| *score >= threshold)
            .take(top)
            .map(|(id, _)| id.as_str())
            .collect();
        let hit = injected.iter().any(|id| case.expect.contains(*id));
        let first_hit = injected.first().is_some_and(|id| case.expect.contains(*id));

        match case.kind {
            Kind::Relevant => {
                relevant += 1.0;
                recalled += f64::from(u8::from(hit));
                top1 += f64::from(u8::from(first_hit));
                correct += f64::from(u8::from(hit));
            }
            Kind::Offtopic => {
                offtopic += 1.0;
                inj_off += f64::from(u8::from(!injected.is_empty()));
            }
            Kind::Adjacent => {
                adjacent += 1.0;
                inj_adj += f64::from(u8::from(!injected.is_empty()));
            }
        }
        if !injected.is_empty() {
            injections += 1.0;
            injected_total += injected.len() as f64;
            token_total +=
                CONTEXT_HEADER_TOKENS + injected.iter().map(|id| tokens_of(id)).sum::<f64>();
        }
    }

    let n = cases.len() as f64;
    GateRow {
        threshold,
        recall: ratio(recalled, relevant),
        top1_correct: ratio(top1, relevant),
        false_injection_offtopic: ratio(inj_off, offtopic),
        false_injection_adjacent: ratio(inj_adj, adjacent),
        precision: (injections > 0.0).then(|| correct / injections),
        mean_injected: ratio(injected_total, n),
        mean_tokens: ratio(token_total, n),
    }
}

/// Kilobytes on a `/proc/<pid>/status` line such as `VmRSS:   123 kB`.
pub fn proc_status_kb(status: &str, key: &str) -> Option<u64> {
    status
        .lines()
        .find_map(|line| line.strip_prefix(key)?.strip_prefix(':'))
        .and_then(|rest| rest.split_whitespace().next())
        .and_then(|number| number.parse().ok())
}

/// utime + stime clock ticks from `/proc/<pid>/stat`; the command name may
/// contain spaces and parentheses, so fields are counted after the last `)`.
pub fn proc_cpu_ticks(stat: &str) -> Option<u64> {
    let (_, after_comm) = stat.rsplit_once(')')?;
    let fields: Vec<&str> = after_comm.split_whitespace().collect();
    let utime: u64 = fields.get(11)?.parse().ok()?;
    let stime: u64 = fields.get(12)?.parse().ok()?;
    utime.checked_add(stime)
}

/// Deterministic unit vectors, for sizing runs without a model.
pub fn synthetic_vectors(n: usize, dims: usize, seed: u64) -> Vec<Vec<f32>> {
    // xorshift64*; the seed is mixed and forced odd so it is never zero.
    let mut state = seed.wrapping_mul(0x9E37_79B9_7F4A_7C15) | 1;
    let mut next = move || {
        state ^= state >> 12;
        state ^= state << 25;
        state ^= state >> 27;
        let bits = state.wrapping_mul(0x2545_F491_4F6C_DD1D) >> 40;
        (bits as f32 / (1_u64 << 24) as f32) * 2.0 - 1.0
    };
    (0..n)
        .map(|_| {
            let raw: Vec<f32> = (0..dims).map(|_| next()).collect();
            let norm = raw
                .iter()
                .map(|x| x * x)
                .sum::<f32>()
                .sqrt()
                .max(f32::EPSILON);
            raw.into_iter().map(|x| x / norm).collect()
        })
        .collect()
}

/// Rough tokens for `bytes` of English or code; only for sizing context.
pub fn approx_tokens(bytes: usize) -> f64 {
    bytes as f64 / 4.0
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used, clippy::indexing_slicing)]
mod tests {
    use super::*;

    fn close(a: f64, b: f64) -> bool {
        (a - b).abs() < 1e-9
    }

    #[test]
    fn percentile_uses_nearest_rank() {
        let v: Vec<f64> = (1..=100).map(f64::from).collect();
        assert!(close(percentile(&v, 50.0), 50.0));
        assert!(close(percentile(&v, 95.0), 95.0));
        assert!(close(percentile(&v, 99.0), 99.0));
        assert!(close(percentile(&v, 100.0), 100.0));
        assert!(close(percentile(&v, 0.0), 1.0));
    }

    #[test]
    fn percentile_of_one_value_is_that_value() {
        assert!(close(percentile(&[7.0], 99.0), 7.0));
    }

    #[test]
    fn summarise_sorts_and_reports_extremes() {
        let s = summarise(&[5.0, 1.0, 3.0, 2.0, 4.0]).unwrap();
        assert_eq!(s.n, 5);
        assert!(close(s.mean, 3.0) && close(s.min, 1.0) && close(s.max, 5.0));
        assert!(close(s.p50, 3.0));
    }

    #[test]
    fn summarise_of_nothing_is_none() {
        assert_eq!(summarise(&[]), None);
    }

    fn case(kind: Kind, expect: &[&str], scored: &[(&str, f64)]) -> Case {
        Case {
            kind,
            expect: expect.iter().map(|s| (*s).to_owned()).collect(),
            scored: scored.iter().map(|(i, s)| ((*i).to_owned(), *s)).collect(),
        }
    }

    fn ten_tokens(_: &str) -> f64 {
        10.0
    }

    fn cases() -> Vec<Case> {
        vec![
            // hit at rank 1
            case(
                Kind::Relevant,
                &["a"],
                &[("a", 0.9), ("x", 0.8), ("y", 0.5)],
            ),
            // expected at rank 2, so recall yes, top1 no
            case(Kind::Relevant, &["b"], &[("x", 0.85), ("b", 0.8)]),
            // expected below the threshold: a miss, nothing injected
            case(Kind::Relevant, &["c"], &[("c", 0.6)]),
            case(Kind::Offtopic, &[], &[("x", 0.9)]),
            case(Kind::Offtopic, &[], &[("x", 0.3)]),
            case(Kind::Adjacent, &[], &[("x", 0.2)]),
        ]
    }

    #[test]
    fn gate_row_counts_recall_and_top1_over_relevant_prompts_only() {
        let row = gate_row(&cases(), 0.7, 3, &ten_tokens);
        assert!(close(row.recall, 2.0 / 3.0));
        assert!(close(row.top1_correct, 1.0 / 3.0));
    }

    #[test]
    fn gate_row_reports_false_injection_per_negative_kind() {
        let row = gate_row(&cases(), 0.7, 3, &ten_tokens);
        assert!(close(row.false_injection_offtopic, 0.5));
        assert!(close(row.false_injection_adjacent, 0.0));
    }

    #[test]
    fn gate_row_precision_is_correct_injections_over_all_injections() {
        // injections: rel-a (correct), rel-b (correct), offtopic-0.9 (wrong)
        let row = gate_row(&cases(), 0.7, 3, &ten_tokens);
        assert!(close(row.precision.unwrap(), 2.0 / 3.0));
    }

    #[test]
    fn gate_row_precision_is_none_when_nothing_is_injected() {
        assert_eq!(gate_row(&cases(), 0.99, 3, &ten_tokens).precision, None);
    }

    #[test]
    fn gate_row_top_limits_injected_count_and_tokens() {
        let row = gate_row(&cases(), 0.7, 1, &ten_tokens);
        // injected counts: 1, 1, 0, 1, 0, 0
        assert!(close(row.mean_injected, 0.5));
        // 3 prompts inject: 10 tokens + header each, over 6 prompts
        assert!(close(
            row.mean_tokens,
            3.0 * (10.0 + CONTEXT_HEADER_TOKENS) / 6.0
        ));
    }

    #[test]
    fn gate_row_on_no_cases_is_all_zero() {
        let row = gate_row(&[], 0.7, 3, &ten_tokens);
        assert!(close(row.recall, 0.0) && close(row.mean_tokens, 0.0));
    }

    #[test]
    fn proc_status_kb_reads_the_named_line() {
        let status = "Name:\tllama-server\nVmHWM:\t  400000 kB\nVmRSS:\t  312345 kB\n";
        assert_eq!(proc_status_kb(status, "VmRSS"), Some(312_345));
        assert_eq!(proc_status_kb(status, "VmHWM"), Some(400_000));
        assert_eq!(proc_status_kb(status, "VmSwap"), None);
    }

    #[test]
    fn proc_cpu_ticks_sums_utime_and_stime_after_the_command_name() {
        // comm contains a space and a parenthesis on purpose
        let stat = "123 (llama (server)) S 1 2 3 4 5 6 7 8 9 10 250 40 0 0 20 0 1 0";
        assert_eq!(proc_cpu_ticks(stat), Some(290));
    }

    #[test]
    fn proc_cpu_ticks_rejects_a_truncated_line() {
        assert_eq!(proc_cpu_ticks("123 (x) S 1 2"), None);
    }

    #[test]
    fn synthetic_vectors_are_unit_length_and_deterministic() {
        let a = synthetic_vectors(5, 16, 42);
        assert_eq!(a.len(), 5);
        for v in &a {
            assert_eq!(v.len(), 16);
            let norm: f32 = v.iter().map(|x| x * x).sum::<f32>().sqrt();
            assert!((norm - 1.0).abs() < 1e-4);
        }
        assert_eq!(a, synthetic_vectors(5, 16, 42));
        assert_ne!(a, synthetic_vectors(5, 16, 43));
    }

    #[test]
    fn approx_tokens_is_a_quarter_of_the_bytes() {
        assert!(close(approx_tokens(4000), 1000.0));
    }
}
