#include <security/pam_appl.h>

#include <stdio.h>
#include <stdlib.h>

static int conversation(int num_msg, const struct pam_message **msg,
                        struct pam_response **resp, void *appdata_ptr) {
    (void)appdata_ptr;

    struct pam_response *responses = calloc((size_t)num_msg, sizeof(*responses));
    if (responses == NULL) {
        return PAM_BUF_ERR;
    }

    for (int i = 0; i < num_msg; i++) {
        if (msg[i]->msg != NULL) {
            fprintf(stderr, "%s\n", msg[i]->msg);
        }
    }

    *resp = responses;
    return PAM_SUCCESS;
}

int main(int argc, char **argv) {
    const char *service = argc > 1 ? argv[1] : "passcode-test";
    const char *user = argc > 2 ? argv[2] : "root";
    struct pam_conv conv = {
        .conv = conversation,
        .appdata_ptr = NULL,
    };
    pam_handle_t *pamh = NULL;

    int rc = pam_start(service, user, &conv, &pamh);
    if (rc == PAM_SUCCESS) {
        rc = pam_authenticate(pamh, 0);
    }
    if (rc == PAM_SUCCESS) {
        rc = pam_acct_mgmt(pamh, 0);
    }

    fprintf(stderr, "pam result: %s\n", pam_strerror(pamh, rc));
    pam_end(pamh, rc);
    return rc == PAM_SUCCESS ? 0 : 1;
}

