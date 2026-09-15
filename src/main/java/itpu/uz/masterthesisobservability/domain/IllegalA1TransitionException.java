package itpu.uz.masterthesisobservability.domain;

public class IllegalA1TransitionException extends RuntimeException {
    public IllegalA1TransitionException(String txnRef, A1Status from, A1Status to) {
        super("A1 transaction %s cannot move from %s to %s".formatted(txnRef, from, to));
    }
}
