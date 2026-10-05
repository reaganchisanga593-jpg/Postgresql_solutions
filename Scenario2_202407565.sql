DROP TABLE IF EXISTS reservations CASCADE;
DROP TABLE IF EXISTS lab_sessions CASCADE;
DROP PROCEDURE IF EXISTS reserve_workstations(INT, VARCHAR, INT);
DROP PROCEDURE IF EXISTS cancel_reservation(INT);

CREATE TABLE lab_sessions (
    session_id          SERIAL PRIMARY KEY,
    session_name        VARCHAR(100) NOT NULL,
    available_ws        INT NOT NULL CHECK (available_ws >= 0)
);

CREATE TABLE reservations (
    reservation_id  SERIAL PRIMARY KEY,
    session_id      INT REFERENCES lab_sessions(session_id),
    lecturer        VARCHAR(50),
    workstations    INT NOT NULL CHECK (workstations > 0),
    status          VARCHAR(20) DEFAULT 'ACTIVE' 
);

INSERT INTO lab_sessions (session_name, available_ws) VALUES
('Monday 08:00 - Databases',   20),
('Tuesday 10:00 - Networks',    2),
('Wednesday 14:00 - AI Lab',   15);

DO $$
DECLARE v_ws INT;
BEGIN
    SELECT available_ws INTO v_ws FROM lab_sessions WHERE session_id = 2;
    IF v_ws = 0 THEN
        RAISE NOTICE 'Session 2: FULL';
    ELSIF v_ws <= 3 THEN
        RAISE NOTICE 'Session 2: NEARLY FULL (%)', v_ws;
    ELSE
        RAISE NOTICE 'Session 2: ENOUGH WORKSTATIONS (%)', v_ws;
    END IF;
END $$;

DO $$
DECLARE i INT := 1;
BEGIN
    WHILE i <= 3 LOOP
        RAISE NOTICE 'Session preparation reminder %', i;
        i := i + 1;
    END LOOP;

    FOR w IN 1..3 LOOP
        RAISE NOTICE 'Workstation check number %', w;
    END LOOP;
END $$;

CREATE OR REPLACE PROCEDURE reserve_workstations(
    p_session INT, p_lecturer VARCHAR, p_ws INT
)
LANGUAGE plpgsql AS $$
DECLARE v_avail INT;
BEGIN
    IF p_ws <= 0 THEN
        RAISE EXCEPTION 'Invalid workstation count: %', p_ws;
    END IF;

    SELECT available_ws INTO v_avail FROM lab_sessions
    WHERE session_id = p_session FOR UPDATE;

    IF v_avail IS NULL THEN
        RAISE EXCEPTION 'Session % not found', p_session;
    END IF;

    IF v_avail < p_ws THEN
        RAISE EXCEPTION 'Not enough workstations (available=%, requested=%)',
              v_avail, p_ws;
    END IF;

    UPDATE lab_sessions SET available_ws = available_ws - p_ws
    WHERE session_id = p_session;

    INSERT INTO reservations(session_id, lecturer, workstations, status)
    VALUES (p_session, p_lecturer, p_ws, 'ACTIVE');

    RAISE NOTICE 'Reserved % workstation(s) for % in session %',
                 p_ws, p_lecturer, p_session;
END $$;

CALL reserve_workstations(1, 'Dr. Mwansa', 5);
CALL reserve_workstations(3, 'Dr. Banda',  4);

DO $$
BEGIN
    CALL reserve_workstations(2, 'Dr. Phiri', 10);
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Expected failure: %', SQLERRM;
END $$;

SELECT * FROM lab_sessions;
SELECT * FROM reservations;

CREATE OR REPLACE PROCEDURE cancel_reservation(p_res_id INT)
LANGUAGE plpgsql AS $$
DECLARE v_status VARCHAR; v_sess INT; v_ws INT;
BEGIN
    SELECT status, session_id, workstations
      INTO v_status, v_sess, v_ws
    FROM reservations WHERE reservation_id = p_res_id FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Reservation % not found', p_res_id;
    END IF;

    IF v_status = 'CANCELLED' THEN
        RAISE NOTICE 'Reservation % already cancelled - no change', p_res_id;
        RETURN;
    END IF;

    UPDATE lab_sessions SET available_ws = available_ws + v_ws
    WHERE session_id = v_sess;

    UPDATE reservations SET status = 'CANCELLED'
    WHERE reservation_id = p_res_id;

    RAISE NOTICE 'Reservation % cancelled, % workstation(s) released', p_res_id, v_ws;
END $$;

CALL cancel_reservation(1);
CALL cancel_reservation(1);  

DO $$
DECLARE
    cur CURSOR FOR SELECT session_id, session_name, available_ws
                   FROM lab_sessions WHERE available_ws <= 3;
    r RECORD;
BEGIN
    OPEN cur;
    LOOP
        FETCH cur INTO r; EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Low availability -> Session % (%) : % ws',
                     r.session_id, r.session_name, r.available_ws;
    END LOOP;
    CLOSE cur;
END $$;

DO $$
BEGIN
    CALL reserve_workstations(1, 'Dr. Test', 0);
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Handled invalid quantity: %', SQLERRM;
END $$;

SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;