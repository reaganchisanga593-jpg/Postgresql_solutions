DROP TABLE IF EXISTS allocations CASCADE;
DROP TABLE IF EXISTS hostel_rooms CASCADE;
DROP PROCEDURE IF EXISTS allocate_room(INT, VARCHAR);
DROP PROCEDURE IF EXISTS check_out(INT);

CREATE TABLE hostel_rooms (
    room_id        SERIAL PRIMARY KEY,
    room_number    VARCHAR(10) NOT NULL,
    available_beds INT NOT NULL CHECK (available_beds >= 0)
);

CREATE TABLE allocations (
    allocation_id SERIAL PRIMARY KEY,
    room_id       INT REFERENCES hostel_rooms(room_id),
    student_no    VARCHAR(20) NOT NULL,
    status        VARCHAR(20) DEFAULT 'ALLOCATED'
);

INSERT INTO hostel_rooms (room_number, available_beds) VALUES
('A101', 3),
('B202', 1),
('C303', 5);

DO $$
DECLARE v_beds INT;
BEGIN
    SELECT available_beds INTO v_beds FROM hostel_rooms WHERE room_id = 2;
    IF v_beds = 0 THEN
        RAISE NOTICE 'Room 2: FULL';
    ELSIF v_beds = 1 THEN
        RAISE NOTICE 'Room 2: ONE SPACE LEFT';
    ELSE
        RAISE NOTICE 'Room 2: SEVERAL SPACES (%)', v_beds;
    END IF;
END $$;

DO $$
DECLARE i INT := 1;
BEGIN
    WHILE i <= 3 LOOP
        RAISE NOTICE 'Hostel inspection day %', i;
        i := i + 1;
    END LOOP;
    FOR r IN 1..3 LOOP
        RAISE NOTICE 'Room check number %', r;
    END LOOP;
END $$;

CREATE OR REPLACE PROCEDURE allocate_room(p_room INT, p_student VARCHAR)
LANGUAGE plpgsql AS $$
DECLARE v_beds INT;
BEGIN
    IF p_student IS NULL OR TRIM(p_student) = '' THEN
        RAISE EXCEPTION 'Invalid student number (blank)';
    END IF;

    SELECT available_beds INTO v_beds FROM hostel_rooms
    WHERE room_id = p_room FOR UPDATE;

    IF v_beds IS NULL THEN
        RAISE EXCEPTION 'Room % does not exist', p_room;
    END IF;

    IF v_beds = 0 THEN
        RAISE EXCEPTION 'Room % is full', p_room;
    END IF;

    UPDATE hostel_rooms SET available_beds = available_beds - 1
    WHERE room_id = p_room;

    INSERT INTO allocations(room_id, student_no, status)
    VALUES (p_room, p_student, 'ALLOCATED');

    RAISE NOTICE 'Allocated room % to student %', p_room, p_student;
END $$;

CALL allocate_room(1, 'STU001');
CALL allocate_room(3, 'STU002');

CALL allocate_room(2, 'STU003');
DO $$
BEGIN
    CALL allocate_room(2, 'STU004'); 
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Expected failure: %', SQLERRM;
END $$;

SELECT * FROM hostel_rooms;
SELECT * FROM allocations;

CREATE OR REPLACE PROCEDURE check_out(p_alloc INT)
LANGUAGE plpgsql AS $$
DECLARE v_status VARCHAR; v_room INT;
BEGIN
    SELECT status, room_id INTO v_status, v_room
    FROM allocations WHERE allocation_id = p_alloc FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Allocation % not found', p_alloc;
    END IF;

    IF v_status = 'CHECKED_OUT' THEN
        RAISE NOTICE 'Allocation % already checked out - no change', p_alloc;
        RETURN;
    END IF;

    UPDATE hostel_rooms SET available_beds = available_beds + 1
    WHERE room_id = v_room;

    UPDATE allocations SET status = 'CHECKED_OUT'
    WHERE allocation_id = p_alloc;

    RAISE NOTICE 'Allocation % checked out; bed in room % freed', p_alloc, v_room;
END $$;

CALL check_out(1);
CALL check_out(1);   

DO $$
DECLARE
    cur CURSOR FOR SELECT room_id, room_number, available_beds
                   FROM hostel_rooms WHERE available_beds <= 1;
    r RECORD;
BEGIN
    OPEN cur;
    LOOP
        FETCH cur INTO r; EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Nearly full -> Room % (%) : % bed(s)',
                     r.room_id, r.room_number, r.available_beds;
    END LOOP;
    CLOSE cur;
END $$;

DO $$
BEGIN
    CALL allocate_room(1, '');
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Handled invalid input: %', SQLERRM;
END $$;

SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;