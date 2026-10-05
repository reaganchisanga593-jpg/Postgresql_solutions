DROP TABLE IF EXISTS dispensing_records CASCADE;
DROP TABLE IF EXISTS medicines CASCADE;
DROP PROCEDURE IF EXISTS dispense_medicine(INT, VARCHAR, INT);
DROP PROCEDURE IF EXISTS reverse_dispensing(INT);

CREATE TABLE medicines (
    medicine_id   SERIAL PRIMARY KEY,
    name          VARCHAR(100) NOT NULL,
    stock_qty     INT NOT NULL CHECK (stock_qty >= 0)
);

CREATE TABLE dispensing_records (
    record_id    SERIAL PRIMARY KEY,
    medicine_id  INT REFERENCES medicines(medicine_id),
    student_no   VARCHAR(20),
    quantity     INT NOT NULL,
    status       VARCHAR(20) DEFAULT 'DISPENSED'
);

INSERT INTO medicines (name, stock_qty) VALUES
('Paracetamol', 100),
('Amoxicillin', 5),
('Ibuprofen',   0);

DO $$
DECLARE v_stock INT;
BEGIN
    SELECT stock_qty INTO v_stock FROM medicines WHERE medicine_id = 2;
    IF v_stock = 0 THEN
        RAISE NOTICE 'Medicine 2: OUT OF STOCK';
    ELSIF v_stock <= 10 THEN
        RAISE NOTICE 'Medicine 2: LOW ON STOCK (%)', v_stock;
    ELSE
        RAISE NOTICE 'Medicine 2: SUFFICIENTLY STOCKED (%)', v_stock;
    END IF;
END $$;

DO $$
DECLARE i INT := 1;
BEGIN
    WHILE i <= 3 LOOP
        RAISE NOTICE 'Stock review day %', i;
        i := i + 1;
    END LOOP;
    FOR s IN 1..3 LOOP
        RAISE NOTICE 'Shelf inspection number %', s;
    END LOOP;
END $$;

CREATE OR REPLACE PROCEDURE dispense_medicine(
    p_med INT, p_student VARCHAR, p_qty INT
)
LANGUAGE plpgsql AS $$
DECLARE v_stock INT;
BEGIN
    IF p_qty <= 0 THEN
        RAISE EXCEPTION 'Invalid dispensing quantity: %', p_qty;
    END IF;

    SELECT stock_qty INTO v_stock FROM medicines
    WHERE medicine_id = p_med FOR UPDATE;

    IF v_stock IS NULL THEN
        RAISE EXCEPTION 'Medicine % not found', p_med;
    END IF;

    IF v_stock < p_qty THEN
        RAISE EXCEPTION 'Insufficient stock (available=%, requested=%)',
              v_stock, p_qty;
    END IF;

    UPDATE medicines SET stock_qty = stock_qty - p_qty
    WHERE medicine_id = p_med;

    INSERT INTO dispensing_records(medicine_id, student_no, quantity, status)
    VALUES (p_med, p_student, p_qty, 'DISPENSED');

    RAISE NOTICE 'Dispensed % of medicine % to %', p_qty, p_med, p_student;
END $$;

CALL dispense_medicine(1, 'STU001', 10);
CALL dispense_medicine(2, 'STU002', 3);

DO $$
BEGIN
    CALL dispense_medicine(2, 'STU003', 50);
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Expected failure: %', SQLERRM;
END $$;

SELECT * FROM medicines;
SELECT * FROM dispensing_records;

CREATE OR REPLACE PROCEDURE reverse_dispensing(p_rec INT)
LANGUAGE plpgsql AS $$
DECLARE v_status VARCHAR; v_med INT; v_qty INT;
BEGIN
    SELECT status, medicine_id, quantity
      INTO v_status, v_med, v_qty
    FROM dispensing_records WHERE record_id = p_rec FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Dispensing record % not found', p_rec;
    END IF;

    IF v_status = 'REVERSED' THEN
        RAISE NOTICE 'Record % already reversed - no change', p_rec;
        RETURN;
    END IF;

    UPDATE medicines SET stock_qty = stock_qty + v_qty
    WHERE medicine_id = v_med;

    UPDATE dispensing_records SET status = 'REVERSED'
    WHERE record_id = p_rec;

    RAISE NOTICE 'Record % reversed; % unit(s) restored', p_rec, v_qty;
END $$;

CALL reverse_dispensing(1);
CALL reverse_dispensing(1);  

DO $$
DECLARE
    cur CURSOR FOR SELECT medicine_id, name, stock_qty
                   FROM medicines WHERE stock_qty <= 10;
    r RECORD;
BEGIN
    OPEN cur;
    LOOP
        FETCH cur INTO r; EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Low stock -> Medicine % (%) : % units',
                     r.medicine_id, r.name, r.stock_qty;
    END LOOP;
    CLOSE cur;
END $$;

DO $$
BEGIN
    CALL dispense_medicine(1, 'STU009', -5);
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Handled invalid input: %', SQLERRM;
END $$;

SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY record_id;