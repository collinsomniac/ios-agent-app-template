//! C ABI surface of the Rust core. Every exported fn is `extern "C"` + `#[no_mangle]`.
//! Strings returned to Swift are heap-allocated here and must be freed with `core_free_string`.
use std::ffi::CString;
use std::os::raw::c_char;

#[no_mangle]
pub extern "C" fn core_version() -> *mut c_char {
    let s = format!("rust-core {} ({})", env!("CARGO_PKG_VERSION"), std::env::consts::ARCH);
    CString::new(s).map(|c| c.into_raw()).unwrap_or(std::ptr::null_mut())
}

#[no_mangle]
pub extern "C" fn core_free_string(p: *mut c_char) {
    if !p.is_null() {
        unsafe { drop(CString::from_raw(p)) };
    }
}

#[no_mangle]
pub extern "C" fn core_add(a: i64, b: i64) -> i64 {
    a.wrapping_add(b)
}

#[cfg(test)]
mod tests {
    #[test]
    fn add() { assert_eq!(super::core_add(2, 40), 42); }
}
