//! Linked refunds netted in the statistics (#714, opt-in): with `stats.net_refunds` on, every
//! active refund link takes its allocated amount out of the sums. The refund endpoint counts
//! `amount - allocated` (a full refund counts zero), the original `amount + allocated` (a
//! refunded purchase counts only what was kept). Bookings, their list rows and balances never
//! change: only the aggregates read amounts through the SQL functions registered here.
//!
//! `refund_offset(id, part)` is the offset of one endpoint (`''` = the whole booking),
//! `refund_offset_total(id)` the sum over all endpoints of a booking. Both read the map the
//! last [`Vault::refund_offsets_ready`] built. Aggregates never call it themselves: they get
//! their SQL from [`Vault::effective_sql`] or `filter_clauses`, which bring the map up to date.

use std::collections::HashMap;
use std::sync::{Arc, PoisonError, RwLock};

use rusqlite::Connection;
use rusqlite::functions::FunctionFlags;

use crate::error::CoreResult;
use crate::vault::Vault;
use crate::vault::cache::DataStamp;

/// The setting (`"1"` = on). Off by default: refund links are documentation only.
pub const NET_REFUNDS_KEY: &str = "stats.net_refunds";

#[derive(Default)]
pub(crate) struct Offsets {
    /// booking id → (sum over its endpoints, offset per part; `""` = whole booking)
    by_booking: HashMap<i64, (i64, HashMap<String, i64>)>,
}

impl Offsets {
    fn add(&mut self, id: i64, part: &str, cents: i64) {
        let entry = self.by_booking.entry(id).or_default();
        entry.0 = entry.0.saturating_add(cents);
        let slot = entry.1.entry(part.to_string()).or_default();
        *slot = slot.saturating_add(cents);
    }

    fn of(&self, id: i64, part: &str) -> i64 {
        self.by_booking
            .get(&id)
            .and_then(|b| b.1.get(part))
            .copied()
            .unwrap_or(0)
    }

    fn total(&self, id: i64) -> i64 {
        self.by_booking.get(&id).map_or(0, |b| b.0)
    }
}

/// The map the SQL functions read, with the (setting, data) state it was built for (`None`:
/// built inside a transaction, rebuilt on the next call).
#[derive(Default)]
pub(crate) struct OffsetSlot(Arc<RwLock<(Option<(bool, DataStamp)>, Arc<Offsets>)>>);

impl OffsetSlot {
    fn current(&self) -> Arc<Offsets> {
        self.0
            .read()
            .unwrap_or_else(PoisonError::into_inner)
            .1
            .clone()
    }

    /// Registers `refund_offset` and `refund_offset_total` on the vault's connection.
    pub(crate) fn register(&self, conn: &Connection) -> rusqlite::Result<()> {
        let slot = OffsetSlot(self.0.clone());
        conn.create_scalar_function("refund_offset", 2, FunctionFlags::SQLITE_UTF8, move |ctx| {
            let id: i64 = ctx.get(0)?;
            let part: Option<String> = ctx.get(1)?;
            Ok(slot.current().of(id, part.as_deref().unwrap_or("")))
        })?;
        let slot = OffsetSlot(self.0.clone());
        conn.create_scalar_function(
            "refund_offset_total",
            1,
            FunctionFlags::SQLITE_UTF8,
            move |ctx| Ok(slot.current().total(ctx.get(0)?)),
        )
    }
}

impl Vault {
    /// Whether linked refunds are netted in the statistics.
    pub(crate) fn refunds_netted(db: &Connection) -> CoreResult<bool> {
        Ok(Self::setting_inner(db, NET_REFUNDS_KEY)?.is_some_and(|v| v == "1"))
    }

    /// Brings the offsets the SQL functions read up to date with the setting and the data
    /// `db` shows. Every aggregate calls it before a query that uses them.
    pub(crate) fn refund_offsets_ready(&self, db: &Connection) -> CoreResult<()> {
        let on = Self::refunds_netted(db)?;
        let stamp = self.data_stamp(db);
        let slot = &self.refund_offsets.0;
        if slot.read().unwrap_or_else(PoisonError::into_inner).0 == Some((on, stamp)) {
            return Ok(());
        }
        let mut offsets = Offsets::default();
        if on {
            for a in &self.refund_projection(db)?.allocations {
                if let (Some(r), Some(o)) = (&a.refund, &a.original)
                    && a.cents != 0
                {
                    offsets.add(r.0, &r.1, a.cents);
                    offsets.add(o.0, &o.1, a.cents.saturating_neg());
                }
            }
        }
        let built = db.is_autocommit().then_some((on, stamp));
        *slot.write().unwrap_or_else(PoisonError::into_inner) = (built, Arc::new(offsets));
        Ok(())
    }
}

#[uniffi::export]
impl Vault {
    /// Whether linked refunds are netted against their original bookings in the statistics
    /// (category totals and history, budgets, KPI tiles, cash flow, tag totals). Off by default.
    pub fn net_refunds_in_stats(&self) -> Result<bool, crate::error::CoreError> {
        Self::refunds_netted(&*self.db()?)
    }

    /// Turns netting linked refunds in the statistics on or off.
    pub fn set_net_refunds_in_stats(&self, on: bool) -> Result<(), crate::error::CoreError> {
        self.set_setting(
            NET_REFUNDS_KEY.to_string(),
            if on { "1" } else { "" }.to_string(),
        )
    }
}
