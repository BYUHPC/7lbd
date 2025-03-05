/* This disables FIPS mode compliance in smbd. This is not intended to cheat on
 * compliance requirements. This is only to be used in situations where CUI is
 * not and cannot be involved. Alternatively, if you have sufficient other
 * controls in place that protect the confidentiality of the CUI, this may be
 * appropriate to use. An example would be smbd inside of an isolated network
 * namespace where a Windows VM, also inside the isolated namespace, needs to
 * talk to Samba to gain access to files hosted on Linux. This has not been
 * tested with Windows in FIPS mode and is assumed to not work in that case. The
 * "correct" solution in that case is Kerberos/AD authentication.
 *
 * According to "SC.L2-3.13.11 – CUI ENCRYPTION", CMMC Assessment Guide – Level 2 Version 2.13:
 *   Encryption used for other purposes, such as within applications or devices within
 *   the protected environment of the covered OSA information system, would not
 *   need to use FIPS-validated cryptography.
 * Retrieved from https://dodcio.defense.gov/Portals/0/Documents/CMMC/AssessmentGuideL2v2.pdf on March 5, 2025
 *
 * YMMV. This may break things, delete files, send your files to agents from
 * $BAD_COUNTRY, make you non-compliant, drain your bank account, send you to
 * jail, burn down your data center, or simply just not work right. Use only as
 * directed. Ask legal counsel and auditors if gnutls_fips_override is right for
 * you.
 *
 * Compile:
 * gcc -fPIC -shared -O2 -o gnutls_fips_override.so gnutls_fips_override.c
 * 
 * Set LD_PRELOAD=/path/to/gnutls_fips_override.so when running smbd. Example:
 * $ LD_PRELOAD=/path/to/gnutls_fips_override.so smbd ...options...
 *
 */
#include <stdbool.h>

unsigned gnutls_fips140_mode_enabled(void) {
	return 0;
}

bool samba_gnutls_weak_crypto_allowed(void) {
	return true;
}
