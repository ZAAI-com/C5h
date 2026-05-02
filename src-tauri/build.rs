fn main() {
    println!("cargo:rerun-if-changed=capabilities-dev/dev.json");

    let dest = std::path::Path::new("capabilities/dev.json");

    #[cfg(feature = "e2e")]
    {
        let src = std::path::Path::new("capabilities-dev/dev.json");
        let new = std::fs::read(src).expect("failed to read dev capability source");
        let unchanged = std::fs::read(dest).map(|cur| cur == new).unwrap_or(false);
        if !unchanged {
            std::fs::write(dest, new).expect("failed to install dev capability for e2e feature");
        }
    }

    #[cfg(not(feature = "e2e"))]
    {
        match std::fs::remove_file(dest) {
            Ok(()) => {}
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
            Err(e) => panic!(
                "failed to remove stale dev capability at {}: {e}. \
                 A leftover dev.json would link the unauthenticated tauri-pilot socket \
                 into a non-e2e build.",
                dest.display()
            ),
        }
    }

    tauri_build::build()
}
