package itpu.uz.masterthesisobservability.credit;

/** The requested stage is not in CREDIT_STAGE. Loud, because a typo'd stage would otherwise
    produce an event log with a stage nobody can analyse. */
public class UnknownStageException extends RuntimeException {
    public UnknownStageException(String code) {
        super("noma'lum bosqich: " + code);
    }
}
