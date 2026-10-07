use std::str::FromStr;
use std::time::Duration;

use serde::{Deserialize, Serialize};
use thiserror::Error;

use crate::corpus::Chunk;
use crate::retriever::{rank_by_score, RetrieveError, Retriever};

const BATCH_SIZE: usize = 16;
/// Request timeout: the first batch can include a cold model load on CPU.
const REQUEST_TIMEOUT: Duration = Duration::from_secs(300);
/// Keeps a document under a 2048-token server window: identifier-heavy markdown
/// tokenises at ~2.7 chars/token (6000 chars overflowed at 2195 tokens).
const MAX_DOC_CHARS: usize = 4000;

/// How queries and documents are wrapped before embedding.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Preset {
    None,
    /// EmbeddingGemma retrieval prompts, from the model card.
    Gemma,
}

impl Preset {
    fn query(self, query: &str) -> String {
        match self {
            Self::None => query.to_owned(),
            Self::Gemma => format!("task: search result | query: {query}"),
        }
    }

    fn document(self, chunk: &Chunk) -> String {
        let text: String = match self {
            Self::None => chunk.document(),
            Self::Gemma => format!("title: {} | text: {}", chunk.title, chunk.text),
        };
        text.chars().take(MAX_DOC_CHARS).collect()
    }
}

#[derive(Debug, Error)]
#[error("embedder spec {spec:?}: {reason}")]
pub struct SpecError {
    spec: String,
    reason: &'static str,
}

/// `NAME=PRESET@BASE_URL[#DIMS]`, e.g. `gemma2=gemma@http://127.0.0.1:8081#256`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EmbedderSpec {
    pub name: String,
    pub preset: Preset,
    pub base_url: String,
    pub dims: Option<usize>,
}

impl FromStr for EmbedderSpec {
    type Err = SpecError;

    fn from_str(spec: &str) -> Result<Self, SpecError> {
        let fail = |reason| SpecError {
            spec: spec.to_owned(),
            reason,
        };
        let (name, rest) = spec.split_once('=').ok_or_else(|| fail("missing NAME="))?;
        let (preset, location) = rest
            .split_once('@')
            .ok_or_else(|| fail("missing PRESET@URL"))?;
        let preset = match preset {
            "none" => Preset::None,
            "gemma" => Preset::Gemma,
            _ => return Err(fail("preset must be `none` or `gemma`")),
        };
        let (base_url, dims) = match location.split_once('#') {
            Some((url, dims)) => (
                url,
                Some(dims.parse().map_err(|_| fail("DIMS is not a number"))?),
            ),
            None => (location, None),
        };
        if name.is_empty() || base_url.is_empty() {
            return Err(fail("NAME and URL must be non-empty"));
        }
        Ok(Self {
            name: name.to_owned(),
            preset,
            base_url: base_url.to_owned(),
            dims,
        })
    }
}

/// Truncate to `dims` (Matryoshka) then L2-normalise, so cosine is a dot product.
pub fn truncate_normalise(mut vector: Vec<f32>, dims: Option<usize>) -> Vec<f32> {
    if let Some(dims) = dims {
        vector.truncate(dims);
    }
    let norm = vector.iter().map(|x| x * x).sum::<f32>().sqrt();
    if norm > 0.0 {
        for x in &mut vector {
            *x /= norm;
        }
    }
    vector
}

fn dot(a: &[f32], b: &[f32]) -> f64 {
    a.iter().zip(b).map(|(x, y)| f64::from(x * y)).sum()
}

#[derive(Serialize)]
struct EmbedRequest<'a> {
    input: &'a [String],
}

#[derive(Deserialize)]
struct EmbedResponse {
    data: Vec<EmbedItem>,
}

#[derive(Deserialize)]
struct EmbedItem {
    index: usize,
    embedding: Vec<f32>,
}

/// Client for an OpenAI-compatible `/v1/embeddings` endpoint, i.e. `llama-server --embeddings`.
pub struct Embedder {
    spec: EmbedderSpec,
    agent: ureq::Agent,
    ids: Vec<String>,
    matrix: Vec<Vec<f32>>,
    indexed: bool,
}

impl Embedder {
    pub fn new(spec: EmbedderSpec) -> Self {
        let agent = ureq::Agent::config_builder()
            .timeout_global(Some(REQUEST_TIMEOUT))
            .build()
            .into();
        Self {
            spec,
            agent,
            ids: Vec::new(),
            matrix: Vec::new(),
            indexed: false,
        }
    }

    fn embed(&self, inputs: &[String]) -> Result<Vec<Vec<f32>>, RetrieveError> {
        let url = format!("{}/v1/embeddings", self.spec.base_url.trim_end_matches('/'));
        let mut response = self
            .agent
            .post(&url)
            .send_json(&EmbedRequest { input: inputs })
            .map_err(|source| RetrieveError::Http {
                url: url.clone(),
                source: Box::new(source),
            })?;
        let mut body: EmbedResponse =
            response
                .body_mut()
                .read_json()
                .map_err(|source| RetrieveError::Http {
                    url: url.clone(),
                    source: Box::new(source),
                })?;
        if body.data.len() != inputs.len() {
            return Err(RetrieveError::BadResponse {
                url,
                detail: format!("{} inputs but {} embeddings", inputs.len(), body.data.len()),
            });
        }
        body.data.sort_by_key(|item| item.index);
        Ok(body
            .data
            .into_iter()
            .map(|item| truncate_normalise(item.embedding, self.spec.dims))
            .collect())
    }
}

impl Retriever for Embedder {
    fn name(&self) -> &str {
        &self.spec.name
    }

    fn index(&mut self, chunks: &[Chunk]) -> Result<(), RetrieveError> {
        let texts: Vec<String> = chunks
            .iter()
            .map(|chunk| self.spec.preset.document(chunk))
            .collect();
        let mut matrix = Vec::with_capacity(texts.len());
        for batch in texts.chunks(BATCH_SIZE) {
            matrix.extend(self.embed(batch)?);
        }
        self.ids = chunks.iter().map(|c| c.id.clone()).collect();
        self.matrix = matrix;
        self.indexed = true;
        Ok(())
    }

    fn rank(&self, query: &str) -> Result<Vec<String>, RetrieveError> {
        if !self.indexed {
            return Err(RetrieveError::NotIndexed);
        }
        let wrapped = [self.spec.preset.query(query)];
        let vectors = self.embed(&wrapped)?;
        let Some(query_vector) = vectors.first() else {
            return Err(RetrieveError::BadResponse {
                url: self.spec.base_url.clone(),
                detail: "no embedding returned for the query".to_owned(),
            });
        };
        let scores: Vec<f64> = self
            .matrix
            .iter()
            .map(|doc| dot(doc, query_vector))
            .collect();
        Ok(rank_by_score(&self.ids, &scores))
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used, clippy::indexing_slicing)]
mod tests {
    use std::io::{Read, Write};
    use std::net::TcpListener;
    use std::thread;

    use super::*;

    fn chunk(id: &str, title: &str, text: &str) -> Chunk {
        Chunk {
            id: id.to_owned(),
            title: title.to_owned(),
            text: text.to_owned(),
        }
    }

    #[test]
    fn spec_parses_name_preset_url_and_dims() {
        let spec: EmbedderSpec = "g2=gemma@http://127.0.0.1:8081#256".parse().unwrap();
        assert_eq!(
            spec,
            EmbedderSpec {
                name: "g2".to_owned(),
                preset: Preset::Gemma,
                base_url: "http://127.0.0.1:8081".to_owned(),
                dims: Some(256),
            }
        );
    }

    #[test]
    fn spec_dims_are_optional() {
        let spec: EmbedderSpec = "m=none@http://h:1".parse().unwrap();
        assert_eq!(spec.dims, None);
        assert_eq!(spec.preset, Preset::None);
    }

    #[test]
    fn bad_specs_are_rejected_with_a_reason() {
        for (spec, reason) in [
            ("no-equals", "missing NAME="),
            ("n=gemma", "missing PRESET@URL"),
            ("n=weird@http://h", "preset must be"),
            ("n=gemma@http://h#abc", "DIMS is not a number"),
            ("=gemma@http://h", "non-empty"),
        ] {
            let err = spec.parse::<EmbedderSpec>().unwrap_err().to_string();
            assert!(err.contains(reason), "{spec}: {err}");
        }
    }

    #[test]
    fn truncate_normalise_truncates_then_unit_normalises() {
        let v = truncate_normalise(vec![3.0, 4.0, 100.0], Some(2));
        assert_eq!(v.len(), 2);
        assert!((v[0] - 0.6).abs() < 1e-6 && (v[1] - 0.8).abs() < 1e-6);
    }

    #[test]
    fn truncate_normalise_leaves_zero_vector_alone() {
        assert_eq!(truncate_normalise(vec![0.0, 0.0], None), vec![0.0, 0.0]);
    }

    #[test]
    fn gemma_preset_uses_card_prompts() {
        assert_eq!(
            Preset::Gemma.query("why"),
            "task: search result | query: why"
        );
        assert_eq!(
            Preset::Gemma.document(&chunk("i", "T", "body")),
            "title: T | text: body"
        );
    }

    #[test]
    fn documents_are_capped_in_length() {
        let long = chunk("i", "T", &"x".repeat(MAX_DOC_CHARS * 2));
        assert_eq!(Preset::None.document(&long).chars().count(), MAX_DOC_CHARS);
    }

    /// Serve canned `/v1/embeddings` replies over a real socket: vectors are keyed
    /// by which marker word the input contains, so ranking is checkable by hand.
    fn serve_embeddings(connections: usize) -> String {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let base = format!("http://{}", listener.local_addr().unwrap());
        thread::spawn(move || {
            for stream in listener.incoming().take(connections) {
                let mut stream = stream.unwrap();
                let mut buf = vec![0_u8; 65536];
                let mut request = Vec::new();
                loop {
                    let n = stream.read(&mut buf).unwrap();
                    request.extend_from_slice(&buf[..n]);
                    let text = String::from_utf8_lossy(&request);
                    if let Some((head, body)) = text.split_once("\r\n\r\n") {
                        let len: usize = head
                            .lines()
                            .find_map(|l| {
                                l.to_lowercase()
                                    .strip_prefix("content-length: ")
                                    .map(str::to_owned)
                            })
                            .and_then(|v| v.trim().parse().ok())
                            .unwrap_or(0);
                        if body.len() >= len {
                            break;
                        }
                    }
                }
                let text = String::from_utf8_lossy(&request).into_owned();
                let body = text.split_once("\r\n\r\n").unwrap().1;
                let parsed: serde_json::Value = serde_json::from_str(body).unwrap();
                let data: Vec<serde_json::Value> = parsed["input"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .enumerate()
                    .map(|(index, input)| {
                        let s = input.as_str().unwrap();
                        let embedding = if s.contains("alpha") {
                            [1.0, 0.0]
                        } else {
                            [0.0, 1.0]
                        };
                        serde_json::json!({"index": index, "embedding": embedding})
                    })
                    .collect();
                let payload = serde_json::json!({ "data": data }).to_string();
                let reply = format!(
                    "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: {}\r\nconnection: close\r\n\r\n{payload}",
                    payload.len()
                );
                stream.write_all(reply.as_bytes()).unwrap();
            }
        });
        base
    }

    #[test]
    fn ranks_by_cosine_against_a_real_http_server() {
        let base = serve_embeddings(2);
        let spec = EmbedderSpec {
            name: "t".to_owned(),
            preset: Preset::None,
            base_url: base,
            dims: None,
        };
        let mut embedder = Embedder::new(spec);
        embedder
            .index(&[chunk("a", "", "alpha doc"), chunk("b", "", "beta doc")])
            .unwrap();
        assert_eq!(
            embedder.rank("alpha please").unwrap(),
            ["a", "b"].map(str::to_owned)
        );
    }

    #[test]
    fn unreachable_server_error_names_the_url() {
        let spec = EmbedderSpec {
            name: "t".to_owned(),
            preset: Preset::None,
            base_url: "http://127.0.0.1:1".to_owned(),
            dims: None,
        };
        let err = Embedder::new(spec)
            .index(&[chunk("a", "", "x")])
            .unwrap_err();
        assert!(err.to_string().contains("127.0.0.1:1/v1/embeddings"));
    }

    #[test]
    fn rank_before_index_is_an_error() {
        let spec = "t=none@http://127.0.0.1:1".parse().unwrap();
        assert!(matches!(
            Embedder::new(spec).rank("x"),
            Err(RetrieveError::NotIndexed)
        ));
    }
}
