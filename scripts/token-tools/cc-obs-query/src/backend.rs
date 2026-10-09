//! Clients for the three stores. A library API: the CLI wraps it, and so can any
//! other front end.
use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};
use std::time::Duration;

use serde::Deserialize;
use serde_json::Value;

use crate::error::Error;

const REQUEST_TIMEOUT: Duration = Duration::from_secs(10);
/// A W3C trace id is 128 bits, 32 hex digits.
const MAX_TRACE_ID_CHARS: usize = 32;

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Urls {
    #[serde(default)]
    pub grafana: String,
    pub loki: String,
    pub tempo: String,
    pub prometheus: String,
    #[serde(default)]
    pub otlp_http: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct Endpoints {
    pub host: String,
    pub urls: Urls,
    #[serde(default)]
    pub ports: BTreeMap<String, Value>,
}

impl Endpoints {
    /// `CC_OBS_ENDPOINTS`, else `$XDG_CONFIG_HOME/cc-obs/endpoints.json`, else
    /// `~/.config/cc-obs/endpoints.json`.
    pub fn locate(env: impl Fn(&str) -> Option<String>) -> Result<PathBuf, Error> {
        let non_empty = |name: &str| env(name).filter(|v| !v.is_empty());
        if let Some(path) = non_empty("CC_OBS_ENDPOINTS") {
            return Ok(PathBuf::from(path));
        }
        let config = non_empty("XDG_CONFIG_HOME")
            .map(PathBuf::from)
            .or_else(|| non_empty("HOME").map(|h| Path::new(&h).join(".config")))
            .ok_or(Error::EndpointsLocate)?;
        Ok(config.join("cc-obs").join("endpoints.json"))
    }

    pub fn load(path: &Path) -> Result<Self, Error> {
        let text = std::fs::read_to_string(path).map_err(|source| Error::EndpointsRead {
            path: path.to_owned(),
            source,
        })?;
        serde_json::from_str(&text).map_err(|source| Error::EndpointsParse {
            path: path.to_owned(),
            source,
        })
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Sample {
    pub labels: BTreeMap<String, String>,
    pub value: f64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Series {
    pub labels: BTreeMap<String, String>,
    pub points: Vec<(f64, f64)>,
}

/// One Loki entry with every field the store returned: stream labels, structured
/// metadata and, when the line is a JSON object, its keys.
#[derive(Debug, Clone, PartialEq)]
pub struct LogRecord {
    pub ts_ns: String,
    pub fields: BTreeMap<String, String>,
}

#[derive(Debug, Clone, Copy)]
pub struct LogFetch {
    pub page_size: usize,
    pub max_records: usize,
    pub max_pages: usize,
}

#[derive(Debug, Clone, PartialEq)]
pub struct LogPages {
    pub records: Vec<LogRecord>,
    /// The caps stopped the fetch before the window was exhausted.
    pub truncated: bool,
    /// Stretches the paging had to skip, one note each.
    pub gaps: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TraceSummary {
    pub trace_id: String,
    pub root_service: Option<String>,
    pub root_name: Option<String>,
    pub duration_ms: Option<u64>,
}

pub struct Backend {
    agent: ureq::Agent,
    pub endpoints: Endpoints,
}

fn join(base: &str, path: &str) -> String {
    format!("{}{}", base.trim_end_matches('/'), path)
}

fn str_map(value: Option<&Value>) -> BTreeMap<String, String> {
    value
        .and_then(Value::as_object)
        .map(|map| {
            map.iter()
                .filter_map(|(k, v)| scalar_text(v).map(|t| (k.clone(), t)))
                .collect()
        })
        .unwrap_or_default()
}

fn scalar_text(value: &Value) -> Option<String> {
    match value {
        Value::String(s) => Some(s.clone()),
        Value::Number(n) => Some(n.to_string()),
        Value::Bool(b) => Some(b.to_string()),
        _ => None,
    }
}

fn number(value: &Value) -> Option<f64> {
    match value {
        Value::String(s) => s.parse().ok(),
        Value::Number(n) => n.as_f64(),
        _ => None,
    }
}

fn pair(value: &Value) -> Option<(f64, f64)> {
    let items = value.as_array()?;
    Some((number(items.first()?)?, number(items.get(1)?)?))
}

impl Backend {
    pub fn new(endpoints: Endpoints) -> Self {
        let agent: ureq::Agent = ureq::Agent::config_builder()
            .timeout_global(Some(REQUEST_TIMEOUT))
            .build()
            .into();
        Self { agent, endpoints }
    }

    pub fn from_env() -> Result<Self, Error> {
        let path = Endpoints::locate(|name| std::env::var(name).ok())?;
        Ok(Self::new(Endpoints::load(&path)?))
    }

    fn get_text(
        &self,
        operation: &'static str,
        url: &str,
        query: &[(&str, &str)],
    ) -> Result<String, Error> {
        let http = |source: ureq::Error| Error::Http {
            operation,
            url: url.to_owned(),
            source: Box::new(source),
        };
        let mut request = self.agent.get(url);
        for (key, value) in query {
            request = request.query(*key, *value);
        }
        let mut response = request.call().map_err(http)?;
        response.body_mut().read_to_string().map_err(http)
    }

    fn get_json(
        &self,
        operation: &'static str,
        url: &str,
        query: &[(&str, &str)],
    ) -> Result<Value, Error> {
        let text = self.get_text(operation, url, query)?;
        serde_json::from_str(&text).map_err(|source| Error::ResponseJson {
            operation,
            url: url.to_owned(),
            source,
        })
    }

    fn data_result(operation: &'static str, body: &Value) -> Result<Vec<Value>, Error> {
        if body.get("status").and_then(Value::as_str) != Some("success") {
            return Err(Error::BackendRejected {
                operation,
                status: body
                    .get("status")
                    .and_then(Value::as_str)
                    .unwrap_or("unknown")
                    .to_owned(),
                detail: body
                    .get("error")
                    .and_then(Value::as_str)
                    .unwrap_or("no detail")
                    .to_owned(),
            });
        }
        body.get("data")
            .and_then(|d| d.get("result"))
            .and_then(Value::as_array)
            .cloned()
            .ok_or_else(|| Error::ResponseShape {
                operation,
                reason: "missing data.result".to_owned(),
            })
    }

    pub fn prom_instant(&self, query: &str, at: Option<i64>) -> Result<Vec<Sample>, Error> {
        let operation = "prometheus instant query";
        let url = join(&self.endpoints.urls.prometheus, "/api/v1/query");
        let at_text = at.map(|t| t.to_string());
        let mut params = vec![("query", query)];
        if let Some(t) = at_text.as_deref() {
            params.push(("time", t));
        }
        let body = self.get_json(operation, &url, &params)?;
        Ok(Self::data_result(operation, &body)?
            .iter()
            .filter_map(|item| {
                let (_, value) = pair(item.get("value")?)?;
                value.is_finite().then(|| Sample {
                    labels: str_map(item.get("metric")),
                    value,
                })
            })
            .collect())
    }

    pub fn prom_range(
        &self,
        query: &str,
        start: i64,
        end: i64,
        step_secs: u64,
    ) -> Result<Vec<Series>, Error> {
        let operation = "prometheus range query";
        let url = join(&self.endpoints.urls.prometheus, "/api/v1/query_range");
        let (start, end, step) = (start.to_string(), end.to_string(), step_secs.to_string());
        let body = self.get_json(
            operation,
            &url,
            &[
                ("query", query),
                ("start", &start),
                ("end", &end),
                ("step", &step),
            ],
        )?;
        Ok(Self::data_result(operation, &body)?
            .iter()
            .map(|item| Series {
                labels: str_map(item.get("metric")),
                points: item
                    .get("values")
                    .and_then(Value::as_array)
                    .map(|vals| vals.iter().filter_map(pair).collect())
                    .unwrap_or_default(),
            })
            .collect())
    }

    pub fn loki_range(
        &self,
        query: &str,
        start_ns: i64,
        end_ns: i64,
        limit: usize,
    ) -> Result<Vec<LogRecord>, Error> {
        let operation = "loki range query";
        let url = join(&self.endpoints.urls.loki, "/loki/api/v1/query_range");
        let (start, end, limit) = (start_ns.to_string(), end_ns.to_string(), limit.to_string());
        let body = self.get_json(
            operation,
            &url,
            &[
                ("query", query),
                ("start", &start),
                ("end", &end),
                ("limit", &limit),
                ("direction", "forward"),
            ],
        )?;
        let mut records = Vec::new();
        for stream in Self::data_result(operation, &body)? {
            let labels = str_map(stream.get("stream"));
            let values = stream
                .get("values")
                .and_then(Value::as_array)
                .cloned()
                .unwrap_or_default();
            for entry in values {
                let Some(items) = entry.as_array() else {
                    continue;
                };
                let mut fields = BTreeMap::new();
                if let Some(Value::Object(line)) = items
                    .get(1)
                    .and_then(Value::as_str)
                    .and_then(|l| serde_json::from_str(l).ok())
                {
                    fields.extend(
                        line.iter()
                            .filter_map(|(k, v)| scalar_text(v).map(|t| (k.clone(), t))),
                    );
                }
                fields.extend(labels.clone());
                if let Some(meta) = items.get(2) {
                    let inner = meta.get("structuredMetadata").or(Some(meta));
                    fields.extend(str_map(inner));
                }
                records.push(LogRecord {
                    ts_ns: items.first().and_then(scalar_text).unwrap_or_default(),
                    fields,
                });
            }
        }
        Ok(records)
    }

    pub fn loki_paged(
        &self,
        query: &str,
        start_ns: i64,
        end_ns: i64,
        fetch: LogFetch,
    ) -> Result<LogPages, Error> {
        let mut records: Vec<LogRecord> = Vec::new();
        let mut gaps: Vec<String> = Vec::new();
        let mut start = start_ns;
        // Records already kept at timestamp `start`: Loki's start is inclusive, so
        // the next page begins AT the last timestamp and repeats them.
        let mut seen_at_start: BTreeSet<BTreeMap<String, String>> = BTreeSet::new();
        for _ in 0..fetch.max_pages {
            let page = self.loki_range(query, start, end_ns, fetch.page_size)?;
            let full = page.len() >= fetch.page_size;
            let stamp = |r: &LogRecord| r.ts_ns.parse::<i64>().ok();
            let last_ts = page.iter().filter_map(stamp).max();
            let at_last: BTreeSet<_> = page
                .iter()
                .filter(|r| stamp(r) == last_ts)
                .map(|r| r.fields.clone())
                .collect();
            records.extend(
                page.into_iter()
                    .filter(|r| !(stamp(r) == Some(start) && seen_at_start.contains(&r.fields))),
            );
            if !full || last_ts.is_some_and(|ts| ts >= end_ns) {
                return Ok(Self::capped(records, fetch.max_records, false, gaps));
            }
            let Some(last) = last_ts.filter(|_| records.len() < fetch.max_records) else {
                return Ok(Self::capped(records, fetch.max_records, true, gaps));
            };
            if last > start {
                seen_at_start = at_last;
                start = last;
            } else {
                // The whole page sits on one timestamp, so repeating the request
                // would return the same page; the rest of that run is unreachable.
                gaps.push(format!(
                    "loki: more than {} records share timestamp {last}; the rest of that run was skipped",
                    fetch.page_size
                ));
                seen_at_start.clear();
                start = last.saturating_add(1);
            }
        }
        Ok(Self::capped(records, fetch.max_records, true, gaps))
    }

    fn capped(
        mut records: Vec<LogRecord>,
        max_records: usize,
        truncated: bool,
        gaps: Vec<String>,
    ) -> LogPages {
        let over = records.len() > max_records;
        records.truncate(max_records);
        LogPages {
            records,
            truncated: truncated || over,
            gaps,
        }
    }

    pub fn tempo_search(
        &self,
        traceql: &str,
        start_secs: i64,
        end_secs: i64,
        limit: usize,
    ) -> Result<Vec<TraceSummary>, Error> {
        let operation = "tempo search";
        let url = join(&self.endpoints.urls.tempo, "/api/search");
        let (start, end, limit) = (
            start_secs.to_string(),
            end_secs.to_string(),
            limit.to_string(),
        );
        let body = self.get_json(
            operation,
            &url,
            &[
                ("q", traceql),
                ("start", &start),
                ("end", &end),
                ("limit", &limit),
            ],
        )?;
        let traces = body
            .get("traces")
            .and_then(Value::as_array)
            .ok_or_else(|| Error::ResponseShape {
                operation,
                reason: "missing traces".to_owned(),
            })?;
        Ok(traces
            .iter()
            .filter_map(|t| {
                Some(TraceSummary {
                    trace_id: t.get("traceID")?.as_str()?.to_owned(),
                    root_service: t
                        .get("rootServiceName")
                        .and_then(Value::as_str)
                        .map(str::to_owned),
                    root_name: t
                        .get("rootTraceName")
                        .and_then(Value::as_str)
                        .map(str::to_owned),
                    duration_ms: t.get("durationMs").and_then(Value::as_u64),
                })
            })
            .collect())
    }

    pub fn tempo_trace(&self, trace_id: &str) -> Result<Value, Error> {
        let valid = !trace_id.is_empty()
            && trace_id.len() <= MAX_TRACE_ID_CHARS
            && trace_id.bytes().all(|b| b.is_ascii_hexdigit());
        if !valid {
            return Err(Error::BadArgument {
                flag: "trace id",
                value: trace_id.to_owned(),
                reason: format!("a trace id is 1 to {MAX_TRACE_ID_CHARS} hex digits"),
            });
        }
        let url = join(
            &self.endpoints.urls.tempo,
            &format!("/api/traces/{trace_id}"),
        );
        self.get_json("tempo trace fetch", &url, &[])
    }

    /// True when the store's readiness endpoint answers 2xx.
    pub fn ready(&self, store: Store) -> bool {
        let (base, path) = match store {
            Store::Prometheus => (&self.endpoints.urls.prometheus, "/-/ready"),
            Store::Loki => (&self.endpoints.urls.loki, "/ready"),
            Store::Tempo => (&self.endpoints.urls.tempo, "/ready"),
        };
        self.get_text("readiness check", &join(base, path), &[])
            .is_ok()
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Store {
    Prometheus,
    Loki,
    Tempo,
}

impl Store {
    pub const ALL: [Store; 3] = [Store::Prometheus, Store::Loki, Store::Tempo];

    pub fn name(self) -> &'static str {
        match self {
            Store::Prometheus => "prometheus",
            Store::Loki => "loki",
            Store::Tempo => "tempo",
        }
    }
}
