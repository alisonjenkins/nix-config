use serde_json::json;

use super::Ctx;
use crate::backend::Store;
use crate::bounds::Report;
use crate::error::Error;

const GUARD_OVER_BUDGET: &str = "observability_guard_over_budget";

pub struct State {
    pub stores: Vec<(Store, Option<String>)>,
    /// `ok`, `over_budget` (ingestion continues), or `None` when the guard published no metric.
    pub guard: Option<&'static str>,
}

impl State {
    pub fn stores_ok(&self) -> bool {
        self.stores.iter().all(|(_, reason)| reason.is_none())
    }
}

pub fn state(ctx: &Ctx) -> State {
    let stores = Store::ALL
        .iter()
        .map(|s| (*s, ctx.backend.ready(*s).err().map(|e| e.to_string())))
        .collect();
    let guard = ctx
        .backend
        .prom_instant(GUARD_OVER_BUDGET, None)
        .ok()
        .and_then(|samples| samples.iter().map(|s| s.value).reduce(f64::max))
        .map(|v| if v >= 1.0 { "over_budget" } else { "ok" });
    State { stores, guard }
}

pub fn run(ctx: &Ctx) -> Result<Report, Error> {
    let state = state(ctx);
    let guard = match state.guard {
        Some(g) => json!(g),
        None => json!({"value": null, "unavailable": "the disk guard has published no metric"}),
    };
    let mut report = Report::new("health")
        .with("stores_ok", json!(state.stores_ok()))
        .with("guard", guard);
    report.rows = state
        .stores
        .iter()
        .map(|(store, reason)| match reason {
            Some(reason) => json!({"key": store.name(), "value": "down", "reason": reason}),
            None => json!({"key": store.name(), "value": "up"}),
        })
        .collect();
    Ok(report)
}
