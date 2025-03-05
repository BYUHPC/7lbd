#include <stdbool.h>

unsigned gnutls_fips140_mode_enabled(void) {
	return 0;
}

bool samba_gnutls_weak_crypto_allowed(void) {
	return true;
}
