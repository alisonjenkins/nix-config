use std::str::FromStr;
use std::time::Duration;

use serde::{Deserialize, Serialize};
use thiserror::Error;

use crate::corpus::Chunk;
use crate::retriever::{rank_scored, RetrieveError, Retriever};
use crate::vector_cache::{fnv1a, VectorCache};

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
    #[serde(default)]
    model: String,
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
        Self::with_timeout(spec, REQUEST_TIMEOUT)
    }

    pub fn with_timeout(spec: EmbedderSpec, timeout: Duration) -> Self {
        let agent = ureq::Agent::config_builder()
            .timeout_global(Some(timeout))
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
        self.embed_with_model(inputs).map(|(vectors, _)| vectors)
    }

    fn embed_with_model(
        &self,
        inputs: &[String],
    ) -> Result<(Vec<Vec<f32>>, String), RetrieveError> {
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
        let vectors = body
            .data
            .into_iter()
            .map(|item| truncate_normalise(item.embedding, self.spec.dims))
            .collect();
        Ok((vectors, body.model))
    }

    /// The model name the server reports, so a cache is never reused across models.
    pub fn model_id(&self) -> Result<String, RetrieveError> {
        self.embed_with_model(&["model probe".to_owned()])
            .map(|(_, model)| model)
    }

    /// All chunk ids with their cosine score, best first.
    pub fn search(&self, query: &str) -> Result<Vec<(String, f64)>, RetrieveError> {
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
        Ok(rank_scored(&self.ids, &scores))
    }

    /// Index `chunks`, embedding only those whose text is new or changed.
    pub fn index_cached(
        &mut self,
        chunks: &[Chunk],
        cache: &mut VectorCache,
    ) -> Result<IndexStats, RetrieveError> {
        let docs: Vec<(&Chunk, String, u64)> = chunks
            .iter()
            .map(|chunk| {
                let text = self.spec.preset.document(chunk);
                let hash = fnv1a(&text);
                (chunk, text, hash)
            })
            .collect();
        let (fresh, stale): (Vec<_>, Vec<_>) = docs
            .iter()
            .partition(|(chunk, _, hash)| cache.get(&chunk.id, *hash).is_some());
        for batch in stale.chunks(BATCH_SIZE) {
            let inputs: Vec<String> = batch.iter().map(|(_, text, _)| text.clone()).collect();
            let vectors = self.embed(&inputs)?;
            for ((chunk, _, hash), vector) in batch.iter().zip(vectors) {
                cache.put(chunk.id.clone(), *hash, vector);
            }
        }
        cache.retain_ids(&chunks.iter().map(|c| c.id.as_str()).collect());
        let stats = IndexStats {
            embedded: stale.len(),
            reused: fresh.len(),
            missing: 0,
        };
        self.load_cached(chunks, cache);
        Ok(stats)
    }

    /// Index from `cache` alone, with no network; chunks it lacks are left out.
    pub fn load_cached(&mut self, chunks: &[Chunk], cache: &VectorCache) -> IndexStats {
        let mut ids = Vec::new();
        let mut matrix = Vec::new();
        let mut missing = 0_usize;
        for chunk in chunks {
            let hash = fnv1a(&self.spec.preset.document(chunk));
            match cache.get(&chunk.id, hash) {
                Some(vector) => {
                    ids.push(chunk.id.clone());
                    matrix.push(vector.to_vec());
                }
                None => missing = missing.saturating_add(1),
            }
        }
        let reused = ids.len();
        self.ids = ids;
        self.matrix = matrix;
        self.indexed = true;
        IndexStats {
            embedded: 0,
            reused,
            missing,
        }
    }
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct IndexStats {
    pub embedded: usize,
    pub reused: usize,
    pub missing: usize,
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
        Ok(self.search(query)?.into_iter().map(|(id, _)| id).collect())
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used, clippy::indexing_slicing)]
mod tests {
    use std::io::{Read, Write};
    use std::net::TcpListener;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::Arc;
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
    /// The counter is how many inputs the server has embedded so far.
    fn serve_embeddings() -> (String, Arc<AtomicUsize>) {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let base = format!("http://{}", listener.local_addr().unwrap());
        let served = Arc::new(AtomicUsize::new(0));
        let counter = Arc::clone(&served);
        thread::spawn(move || {
            for stream in listener.incoming() {
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
                counter.fetch_add(parsed["input"].as_array().unwrap().len(), Ordering::SeqCst);
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
                let payload =
                    serde_json::json!({ "model": "fake-model", "data": data }).to_string();
                let reply = format!(
                    "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: {}\r\nconnection: close\r\n\r\n{payload}",
                    payload.len()
                );
                stream.write_all(reply.as_bytes()).unwrap();
            }
        });
        (base, served)
    }

    fn fake_spec(base_url: String) -> EmbedderSpec {
        EmbedderSpec {
            name: "t".to_owned(),
            preset: Preset::None,
            base_url,
            dims: None,
        }
    }

    #[test]
    fn model_id_is_read_from_the_server_reply() {
        let (base, _) = serve_embeddings();
        assert_eq!(
            Embedder::new(fake_spec(base)).model_id().unwrap(),
            "fake-model"
        );
    }

    #[test]
    fn search_returns_scored_ids_best_first() {
        let (base, _) = serve_embeddings();
        let mut embedder = Embedder::new(fake_spec(base));
        embedder
            .index(&[chunk("b", "", "beta doc"), chunk("a", "", "alpha doc")])
            .unwrap();
        let hits = embedder.search("alpha please").unwrap();
        assert_eq!(
            hits.iter().map(|(id, _)| id.as_str()).collect::<Vec<_>>(),
            ["a", "b"]
        );
        assert!((hits[0].1 - 1.0).abs() < 1e-6 && hits[1].1.abs() < 1e-6);
    }

    #[test]
    fn index_cached_embeds_only_new_or_changed_chunks() {
        let (base, served) = serve_embeddings();
        let mut cache = VectorCache::new("t");
        let mut embedder = Embedder::new(fake_spec(base));
        let chunks = [chunk("a", "", "alpha doc"), chunk("b", "", "beta doc")];

        let first = embedder.index_cached(&chunks, &mut cache).unwrap();
        assert_eq!((first.embedded, first.reused), (2, 0));
        assert_eq!(served.load(Ordering::SeqCst), 2);

        let second = embedder.index_cached(&chunks, &mut cache).unwrap();
        assert_eq!((second.embedded, second.reused), (0, 2));
        assert_eq!(served.load(Ordering::SeqCst), 2);

        let edited = [
            chunk("a", "", "alpha doc"),
            chunk("b", "", "beta doc, edited"),
        ];
        let third = embedder.index_cached(&edited, &mut cache).unwrap();
        assert_eq!((third.embedded, third.reused), (1, 1));
        assert_eq!(served.load(Ordering::SeqCst), 3);
    }

    #[test]
    fn index_cached_prunes_chunks_that_no_longer_exist() {
        let (base, _) = serve_embeddings();
        let mut cache = VectorCache::new("t");
        let mut embedder = Embedder::new(fake_spec(base));
        embedder
            .index_cached(
                &[chunk("a", "", "alpha"), chunk("b", "", "beta")],
                &mut cache,
            )
            .unwrap();
        embedder
            .index_cached(&[chunk("a", "", "alpha")], &mut cache)
            .unwrap();
        assert_eq!(cache.len(), 1);
    }

    #[test]
    fn load_cached_makes_no_requests_and_reports_chunks_without_a_vector() {
        let (base, served) = serve_embeddings();
        let mut cache = VectorCache::new("t");
        let chunks = [chunk("a", "", "alpha doc"), chunk("b", "", "beta doc")];
        Embedder::new(fake_spec(base))
            .index_cached(&chunks[..1], &mut cache)
            .unwrap();
        let before = served.load(Ordering::SeqCst);

        let mut offline = Embedder::new(fake_spec("http://127.0.0.1:1".to_owned()));
        let stats = offline.load_cached(&chunks, &cache);
        assert_eq!((stats.reused, stats.embedded, stats.missing), (1, 0, 1));
        assert_eq!(served.load(Ordering::SeqCst), before);
    }

    #[test]
    fn ranks_by_cosine_against_a_real_http_server() {
        let (base, _) = serve_embeddings();
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
