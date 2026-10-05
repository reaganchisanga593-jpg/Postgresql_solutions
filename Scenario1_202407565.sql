DROP TABLE IF EXISTS book_loans CASCADE;
DROP TABLE IF EXISTS books CASCADE;
DROP PROCEDURE IF EXISTS borrow_book(INT, VARCHAR, INT);
DROP PROCEDURE IF EXISTS return_book(INT);

CREATE TABLE books (
    book_id          SERIAL PRIMARY KEY,
    title            VARCHAR(100) NOT NULL,
    available_copies INT NOT NULL CHECK (available_copies >= 0)
);

CREATE TABLE book_loans (
    loan_id      SERIAL PRIMARY KEY,
    book_id      INT REFERENCES books(book_id),
    student_no   VARCHAR(20),
    quantity     INT NOT NULL CHECK (quantity > 0),
    status       VARCHAR(20) DEFAULT 'BORROWED' 
);

INSERT INTO books (title, available_copies) VALUES
('Database Systems',        3),
('Operating Systems',       1),
('Discrete Mathematics',    5);

DO $$
DECLARE
    v_copies INT;
BEGIN
    SELECT available_copies INTO v_copies FROM books WHERE book_id = 2;

    IF v_copies = 0 THEN
        RAISE NOTICE 'Book 2: UNAVAILABLE';
    ELSIF v_copies <= 2 THEN
        RAISE NOTICE 'Book 2: LOW ON COPIES (%)', v_copies;
    ELSE
        RAISE NOTICE 'Book 2: SUFFICIENTLY STOCKED (%)', v_copies;
    END IF;
END $$;

DO $$
DECLARE
    i INT := 1;
BEGIN
    
    WHILE i <= 3 LOOP
        RAISE NOTICE 'Overdue reminder number: %', i;
        i := i + 1;
    END LOOP;

    FOR s IN 101..103 LOOP
        RAISE NOTICE 'Library shelf number: %', s;
    END LOOP;
END $$;

CREATE OR REPLACE PROCEDURE borrow_book(
    p_book_id   INT,
    p_student   VARCHAR,
    p_qty       INT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_available INT;
BEGIN
    
    IF p_qty <= 0 THEN
        RAISE EXCEPTION 'Invalid quantity: % (must be > 0)', p_qty;
    END IF;

    SELECT available_copies INTO v_available
    FROM books WHERE book_id = p_book_id FOR UPDATE;

    IF v_available IS NULL THEN
        RAISE EXCEPTION 'Book % does not exist', p_book_id;
    END IF;

    IF v_available < p_qty THEN
        RAISE EXCEPTION 'Not enough copies for book % (available=%, requested=%)',
              p_book_id, v_available, p_qty;
    END IF;

    UPDATE books SET available_copies = available_copies - p_qty
    WHERE book_id = p_book_id;

    INSERT INTO book_loans(book_id, student_no, quantity, status)
    VALUES (p_book_id, p_student, p_qty, 'BORROWED');

    RAISE NOTICE 'Loan recorded: book % to student % (qty %)', p_book_id, p_student, p_qty;
END $$;

CALL borrow_book(1, 'STU001', 1);
CALL borrow_book(3, 'STU002', 2);

DO $$
BEGIN
    CALL borrow_book(2, 'STU003', 5);
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Expected failure: %', SQLERRM;
END $$;

SELECT * FROM books;
SELECT * FROM book_loans;

CREATE OR REPLACE PROCEDURE return_book(p_loan_id INT)
LANGUAGE plpgsql AS $$
DECLARE
    v_status VARCHAR;
    v_book   INT;
    v_qty    INT;
BEGIN
    SELECT status, book_id, quantity INTO v_status, v_book, v_qty
    FROM book_loans WHERE loan_id = p_loan_id FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Loan % does not exist', p_loan_id;
    END IF;

    IF v_status = 'RETURNED' THEN
        RAISE NOTICE 'Loan % already returned - no stock change', p_loan_id;
        RETURN;
    END IF;

    UPDATE books SET available_copies = available_copies + v_qty
    WHERE book_id = v_book;

    UPDATE book_loans SET status = 'RETURNED' WHERE loan_id = p_loan_id;

    RAISE NOTICE 'Loan % returned; % copies restored', p_loan_id, v_qty;
END $$;

CALL return_book(1);
CALL return_book(1);  

DO $$
DECLARE
    cur_books CURSOR FOR
        SELECT book_id, title, available_copies
        FROM books WHERE available_copies <= 2;
    r RECORD;
BEGIN
    OPEN cur_books;
    LOOP
        FETCH cur_books INTO r;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Low stock -> Book % (%) : % copies',
                     r.book_id, r.title, r.available_copies;
    END LOOP;
    CLOSE cur_books;
END $$;

DO $$
BEGIN
    CALL borrow_book(1, 'STU009', 0);
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Handled invalid quantity: %', SQLERRM;
END $$;

SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;