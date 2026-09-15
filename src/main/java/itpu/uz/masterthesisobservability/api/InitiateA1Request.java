package itpu.uz.masterthesisobservability.api;

import jakarta.validation.constraints.*;

import java.math.BigDecimal;

public record InitiateA1Request(
        @NotBlank @Size(max = 64)  String txnRef,
        @NotBlank @Size(max = 34)  String debitAccount,
        @NotBlank @Size(max = 34)  String creditAccount,
        @NotNull @DecimalMin("0.0001") BigDecimal amount,
        @NotBlank @Size(min = 3, max = 3) String currency,
        @Size(max = 24) String channel) { }
