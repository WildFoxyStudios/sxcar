use std::sync::Arc;
use std::time::Duration;

use axum::{
    body::{Body, Bytes},
    extract::State,
    http::StatusCode,
    response::{IntoResponse, Response},
};
use tokio::sync::{OwnedSemaphorePermit, Semaphore};

use crate::AppState;

/// Rutas-cebo: paths que solo tocan escáneres/bots, nunca clientes legítimos.
pub const HONEYPOT_PATHS: &[&str] = &[
    "/.env",
    "/.git/config",
    "/.aws/credentials",
    "/wp-login.php",
    "/wp-admin",
    "/phpmyadmin",
    "/admin.php",
    "/config.php",
    "/server-status",
];

/// Límites duros para que el tarpit NUNCA pueda agotar el origen.
#[derive(Clone, Debug)]
pub struct TarpitConfig {
    pub enabled: bool,
    pub max_concurrent: usize,
    pub drip_interval: Duration,
    pub max_bytes: usize,
}

impl Default for TarpitConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            max_concurrent: 256,
            drip_interval: Duration::from_millis(500),
            max_bytes: 512,
        }
    }
}

impl TarpitConfig {
    pub fn from_env() -> Self {
        let enabled = std::env::var("TARPIT_ENABLED")
            .map(|v| v != "false" && v != "0")
            .unwrap_or(true);
        Self {
            enabled,
            ..Self::default()
        }
    }
}

/// Resultado de intentar atrapar una conexión.
pub enum TarpitDecision {
    /// Atrapar: el permiso vive mientras dure el goteo; al soltarse libera capacidad.
    Trap(OwnedSemaphorePermit),
    /// No atrapar (deshabilitado o tope lleno) → respuesta barata.
    Decline,
}

#[derive(Clone)]
pub struct Tarpit {
    pub config: TarpitConfig,
    sem: Arc<Semaphore>,
}

impl Tarpit {
    pub fn new(config: TarpitConfig) -> Self {
        let sem = Arc::new(Semaphore::new(config.max_concurrent));
        Self { config, sem }
    }

    /// Permisos libres (métricas/tests).
    pub fn available(&self) -> usize {
        self.sem.available_permits()
    }

    /// Decide si atrapar. Si el tope está lleno, declina en lugar de
    /// consumir más recursos del origen.
    pub fn try_trap(&self) -> TarpitDecision {
        if !self.config.enabled {
            return TarpitDecision::Decline;
        }
        match self.sem.clone().try_acquire_owned() {
            Ok(permit) => TarpitDecision::Trap(permit),
            Err(_) => TarpitDecision::Decline,
        }
    }
}

/// Handler de rutas-cebo: gotea bytes lentamente para malgastar el tiempo
/// del bot, con límites estrictos. Si declina, responde 404 barato.
pub async fn handler(State(state): State<AppState>) -> Response {
    match state.tarpit.try_trap() {
        TarpitDecision::Decline => StatusCode::NOT_FOUND.into_response(),
        TarpitDecision::Trap(permit) => {
            let interval = state.tarpit.config.drip_interval;
            let max_bytes = state.tarpit.config.max_bytes;
            let stream = async_stream::stream! {
                let _permit = permit; // liberado al terminar o desconectar
                for _ in 0..max_bytes {
                    tokio::time::sleep(interval).await;
                    yield Ok::<Bytes, std::io::Error>(Bytes::from_static(b"."));
                }
            };
            Response::builder()
                .status(StatusCode::OK)
                .header("content-type", "text/plain; charset=utf-8")
                .body(Body::from_stream(stream))
                .expect("valid tarpit response")
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn cfg(enabled: bool, max_concurrent: usize) -> TarpitConfig {
        TarpitConfig {
            enabled,
            max_concurrent,
            ..TarpitConfig::default()
        }
    }

    #[test]
    fn declines_when_disabled() {
        let t = Tarpit::new(cfg(false, 8));
        assert!(matches!(t.try_trap(), TarpitDecision::Decline));
    }

    #[test]
    fn caps_concurrent_traps_to_protect_origin() {
        let t = Tarpit::new(cfg(true, 2));

        let a = t.try_trap();
        let b = t.try_trap();
        assert!(matches!(a, TarpitDecision::Trap(_)));
        assert!(matches!(b, TarpitDecision::Trap(_)));
        assert_eq!(t.available(), 0);

        // Tope lleno → declina (no consume más recursos del origen).
        assert!(matches!(t.try_trap(), TarpitDecision::Decline));

        // Al soltar un permiso, vuelve a haber capacidad.
        drop(a);
        assert_eq!(t.available(), 1);
        assert!(matches!(t.try_trap(), TarpitDecision::Trap(_)));

        drop(b);
    }
}
