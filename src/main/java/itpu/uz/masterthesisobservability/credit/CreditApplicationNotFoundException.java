package itpu.uz.masterthesisobservability.credit;

public class CreditApplicationNotFoundException extends RuntimeException {
    public CreditApplicationNotFoundException(String ref) {
        super("ariza topilmadi: " + ref);
    }
}
