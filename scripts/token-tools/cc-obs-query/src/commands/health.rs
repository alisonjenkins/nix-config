use serde_json::json;

use super::Ctx;
use crate::backend::Store;
use crate::bounds::Report;
use crate::error::Error;

const GUARD_OVER_BUDGET: &str = "observability_guard_over_budget";

pub struct State {
    pub stores: Vec<(Store, bool)>,
    /// `ok`, `over_budget` (ingestion continues), or `None` when the guard published no metric.
    pub guard: Option<&'static str>,
}

impl State {
    pub fn stores_ok(&self) -> bool {
        self.stores.iter().all(|(_, up)| *up)
    }
}

pub fn state(ctx: &Ctx) -> State {
    let stores = Store::ALL
        .iter()
        .map(|s| (*s, ctx.backend.ready(*s)))
        .collect();
    let guard = ctx
        .backend
        .prom_instant(GUARD_OVER_BUDGET, None)
        .ok()
        .and_then(|samples| samples.first().map(|s| s.value))
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
        .map(|(store, up)| json!({"key": store.name(), "value": if *up { "up" } else { "down" }}))
        .collect();
    Ok(report)
}
