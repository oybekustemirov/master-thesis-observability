package itpu.uz.masterthesisobservability.domain;

public class TxnNotFoundException extends RuntimeException {
    public TxnNotFoundException(String txnRef) {
        super("A1 transaction not found: " + txnRef);
    }
}
