package itpu.uz.masterthesisobservability.domain;

/** The A1 state machine. Terminal states are PROCESSED and REJECTED. */
public enum A1Status {
    INITIATED, VALIDATED, PROCESSED, REJECTED;

    public boolean canTransitionTo(A1Status next) {
        return switch (this) {
            case INITIATED -> next == VALIDATED || next == REJECTED;
            case VALIDATED -> next == PROCESSED || next == REJECTED;
            case PROCESSED, REJECTED -> false;
        };
    }
}
