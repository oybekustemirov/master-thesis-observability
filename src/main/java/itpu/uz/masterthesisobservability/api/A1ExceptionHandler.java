package itpu.uz.masterthesisobservability.api;

import itpu.uz.masterthesisobservability.domain.IllegalA1TransitionException;
import itpu.uz.masterthesisobservability.domain.TxnNotFoundException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestControllerAdvice
class A1ExceptionHandler {

    @ExceptionHandler(TxnNotFoundException.class)
    ProblemDetail notFound(TxnNotFoundException e) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.NOT_FOUND, e.getMessage());
    }

    @ExceptionHandler(IllegalA1TransitionException.class)
    ProblemDetail conflict(IllegalA1TransitionException e) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.CONFLICT, e.getMessage());
    }
}
