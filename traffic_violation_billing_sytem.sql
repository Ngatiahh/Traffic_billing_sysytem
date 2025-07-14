-- Create the database
DROP DATABASE IF EXISTS traffic_billing_system;
CREATE DATABASE IF NOT EXISTS traffic_billing_system;
USE traffic_billing_system;

-- Creating core tables with their constraints
CREATE TABLE drivers (
    driver_id INT AUTO_INCREMENT PRIMARY KEY,
    license_number VARCHAR(20) UNIQUE NOT NULL,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    date_of_birth DATE NOT NULL,
    address VARCHAR(200) NOT NULL,
    city VARCHAR(50) NOT NULL,
    state VARCHAR(30) NOT NULL,
    zip_code VARCHAR(10) NOT NULL,
    phone VARCHAR(15) NOT NULL,
    email VARCHAR(100),
    license_issue_date DATE NOT NULL,
    license_expiry_date DATE NOT NULL,
    license_class VARCHAR(10) NOT NULL,
    CONSTRAINT chk_license_dates CHECK (license_expiry_date > license_issue_date)
);

CREATE TABLE vehicles (
    vehicle_id INT AUTO_INCREMENT PRIMARY KEY,
    vin VARCHAR(17) UNIQUE NOT NULL,
    license_plate VARCHAR(15) UNIQUE NOT NULL,
    make VARCHAR(30) NOT NULL,
    model VARCHAR(30) NOT NULL,
    year YEAR NOT NULL,
    color VARCHAR(20) NOT NULL,
    registered_owner_id INT NOT NULL,
    registration_expiry DATE NOT NULL,
    insurance_policy_number VARCHAR(30),
    insurance_expiry DATE,
    CONSTRAINT fk_vehicle_owner FOREIGN KEY (registered_owner_id)
        REFERENCES drivers(driver_id) ON DELETE RESTRICT
);

CREATE TABLE officers (
    officer_id INT AUTO_INCREMENT PRIMARY KEY,
    badge_number VARCHAR(15) UNIQUE NOT NULL,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    department VARCHAR(50) NOT NULL,
    officer_rank VARCHAR(30),
    hire_date DATE NOT NULL,
    active_status BOOLEAN NOT NULL DEFAULT TRUE,
    supervisor_id INT,
    CONSTRAINT fk_officer_supervisor FOREIGN KEY (supervisor_id)
        REFERENCES officers(officer_id) ON DELETE SET NULL
);

CREATE TABLE violation_types (
    violation_code VARCHAR(10) PRIMARY KEY,
    description VARCHAR(200) NOT NULL,
    base_fine_amount DECIMAL(10,2) NOT NULL,
    is_moving_violation BOOLEAN NOT NULL DEFAULT TRUE,
    points_assigned TINYINT NOT NULL DEFAULT 0,
    CONSTRAINT chk_fine_amount CHECK (base_fine_amount > 0),
    CONSTRAINT chk_points CHECK (points_assigned >= 0)
);

-- Creating transaction tables
CREATE TABLE citations (
    citation_id INT AUTO_INCREMENT PRIMARY KEY,
    citation_number VARCHAR(20) UNIQUE NOT NULL,
    driver_id INT NOT NULL,
    vehicle_id INT,
    officer_id INT NOT NULL,
    violation_date DATETIME NOT NULL,
    violation_location VARCHAR(200) NOT NULL,
    violation_code VARCHAR(10) NOT NULL,
    actual_fine_amount DECIMAL(10,2) NOT NULL,
    issued_date DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status ENUM('issued', 'paid', 'disputed', 'dismissed', 'warrant') NOT NULL DEFAULT 'issued',
    notes TEXT,
    CONSTRAINT fk_citation_driver FOREIGN KEY (driver_id)
        REFERENCES drivers(driver_id) ON DELETE RESTRICT,
    CONSTRAINT fk_citation_vehicle FOREIGN KEY (vehicle_id)
        REFERENCES vehicles(vehicle_id) ON DELETE SET NULL,
    CONSTRAINT fk_citation_officer FOREIGN KEY (officer_id)
        REFERENCES officers(officer_id) ON DELETE RESTRICT,
    CONSTRAINT fk_citation_violation FOREIGN KEY (violation_code)
        REFERENCES violation_types(violation_code) ON DELETE RESTRICT,
    CONSTRAINT chk_violation_date CHECK (violation_date <= issued_date)
);

CREATE TABLE payments (
    payment_id INT AUTO_INCREMENT PRIMARY KEY,
    citation_id INT NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    payment_date DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    payment_method ENUM('cash', 'credit_card', 'debit_card', 'check', 'online') NOT NULL,
    received_by VARCHAR(50),
    transaction_reference VARCHAR(50),
    CONSTRAINT fk_payment_citation FOREIGN KEY (citation_id)
        REFERENCES citations(citation_id) ON DELETE RESTRICT,
    CONSTRAINT chk_payment_amount CHECK (amount > 0)
);

CREATE TABLE court_cases (
    case_id INT AUTO_INCREMENT PRIMARY KEY,
    citation_id INT NOT NULL,
    court_date DATETIME NOT NULL,
    court_location VARCHAR(100) NOT NULL,
    judge_name VARCHAR(100),
    case_outcome ENUM('pending', 'guilty', 'not_guilty', 'dismissed', 'reduced') NOT NULL DEFAULT 'pending',
    adjusted_fine_amount DECIMAL(10,2),
    notes TEXT,
    CONSTRAINT fk_case_citation FOREIGN KEY (citation_id)
        REFERENCES citations(citation_id) ON DELETE RESTRICT,
    CONSTRAINT chk_adjusted_fine CHECK (adjusted_fine_amount IS NULL OR adjusted_fine_amount >= 0)
);

CREATE TABLE driver_points (
    record_id INT AUTO_INCREMENT PRIMARY KEY,
    driver_id INT NOT NULL,
    citation_id INT NOT NULL,
    points_added TINYINT NOT NULL,
    effective_date DATE NOT NULL,
    expiration_date DATE NOT NULL,
    CONSTRAINT fk_points_driver FOREIGN KEY (driver_id)
        REFERENCES drivers(driver_id) ON DELETE CASCADE,
    CONSTRAINT fk_points_citation FOREIGN KEY (citation_id)
        REFERENCES citations(citation_id) ON DELETE RESTRICT,
    CONSTRAINT chk_points_date_range CHECK (expiration_date > effective_date)
);

-- Creating the supporting tables for the core tables and transaction tables
CREATE TABLE payment_plans (
    plan_id INT AUTO_INCREMENT PRIMARY KEY,
    citation_id INT NOT NULL,
    total_amount DECIMAL(10,2) NOT NULL,
    initial_payment DECIMAL(10,2) NOT NULL,
    monthly_payment DECIMAL(10,2) NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    status ENUM('active', 'completed', 'defaulted') NOT NULL DEFAULT 'active',
    CONSTRAINT fk_plan_citation FOREIGN KEY (citation_id)
        REFERENCES citations(citation_id) ON DELETE CASCADE,
    CONSTRAINT chk_plan_dates CHECK (end_date > start_date),
    CONSTRAINT chk_plan_amounts CHECK (initial_payment + (DATEDIFF(end_date, start_date)/30 * monthly_payment) >= total_amount)
);

CREATE TABLE warrants (
    warrant_id INT AUTO_INCREMENT PRIMARY KEY,
    citation_id INT NOT NULL,
    issued_date DATE NOT NULL DEFAULT (CURRENT_DATE),
    amount_due DECIMAL(10,2) NOT NULL,
    status ENUM('active', 'served', 'recalled') NOT NULL DEFAULT 'active',
    notes TEXT,
    CONSTRAINT fk_warrant_citation FOREIGN KEY (citation_id)
        REFERENCES citations(citation_id) ON DELETE CASCADE
);

-- Creating indexes for frequently queried to enhance performance
CREATE INDEX idx_drivers_license ON drivers(license_number);
CREATE INDEX idx_drivers_name ON drivers(last_name, first_name);
CREATE INDEX idx_vehicles_plate ON vehicles(license_plate);
CREATE INDEX idx_citations_number ON citations(citation_number);
CREATE INDEX idx_citations_driver ON citations(driver_id);
CREATE INDEX idx_citations_status ON citations(status);
CREATE INDEX idx_citations_date ON citations(violation_date);
CREATE INDEX idx_payments_citation ON payments(citation_id);
CREATE INDEX idx_court_cases_citation ON court_cases(citation_id);
CREATE INDEX idx_driver_points_driver ON driver_points(driver_id);

 -- Creating view for outstanding citations
CREATE VIEW outstanding_citations AS
SELECT 
    c.citation_number,
    CONCAT(d.first_name, ' ', d.last_name) AS driver_name,
    d.license_number,
    v.license_plate,
    vt.description AS violation,
    c.violation_date,
    c.actual_fine_amount,
    c.issued_date,
    DATEDIFF(CURRENT_DATE, c.issued_date) AS days_outstanding
FROM 
    citations c
JOIN 
    drivers d ON c.driver_id = d.driver_id
LEFT JOIN 
    vehicles v ON c.vehicle_id = v.vehicle_id
JOIN 
    violation_types vt ON c.violation_code = vt.violation_code
WHERE 
    c.status = 'issued' OR c.status = 'warrant';

-- Creating view for driver point accumulations
CREATE VIEW driver_point_totals AS
SELECT 
    d.driver_id,
    d.license_number,
    CONCAT(d.first_name, ' ', d.last_name) AS driver_name,
    SUM(dp.points_added) AS total_points,
    MAX(dp.expiration_date) AS latest_expiration
FROM 
    drivers d
JOIN 
    driver_points dp ON d.driver_id = dp.driver_id
WHERE 
    dp.expiration_date > CURRENT_DATE
GROUP BY 
    d.driver_id, d.license_number, driver_name;

-- Creating view for revenue by violation type
CREATE VIEW revenue_by_violation AS
SELECT 
    vt.violation_code,
    vt.description,
    COUNT(c.citation_id) AS citation_count,
    SUM(p.amount) AS total_revenue,
    AVG(p.amount) AS average_revenue
FROM 
    violation_types vt
LEFT JOIN 
    citations c ON vt.violation_code = c.violation_code
LEFT JOIN 
    payments p ON c.citation_id = p.citation_id
GROUP BY 
    vt.violation_code, vt.description;
    
    -- Declaring the procedure to issue a new citation
DELIMITER //
CREATE PROCEDURE issue_citation(
    IN p_license_number VARCHAR(20),
    IN p_license_plate VARCHAR(15),
    IN p_officer_id INT,
    IN p_violation_code VARCHAR(10),
    IN p_violation_date DATETIME,
    IN p_location VARCHAR(200),
    IN p_notes TEXT,
    OUT p_citation_number VARCHAR(20)
    )
BEGIN
    DECLARE v_driver_id INT;
    DECLARE v_vehicle_id INT;
    DECLARE v_base_fine DECIMAL(10,2);
    DECLARE v_citation_num VARCHAR(20);
    
    -- Get driver ID from license number
    SELECT driver_id INTO v_driver_id FROM drivers WHERE license_number = p_license_number;
    IF v_driver_id IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Driver not found';
    END IF;
    
    -- Get vehicle ID if provided
    IF p_license_plate IS NOT NULL THEN
        SELECT vehicle_id INTO v_vehicle_id FROM vehicles WHERE license_plate = p_license_plate;
        IF v_vehicle_id IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Vehicle not found';
        END IF;
    END IF;
    
    -- Get base fine amount
    SELECT base_fine_amount INTO v_base_fine FROM violation_types WHERE violation_code = p_violation_code;
    IF v_base_fine IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Violation type not found';
    END IF;
    
    -- Generate citation number (YYMMDD-XXXXX)
    SET v_citation_num = CONCAT(
        DATE_FORMAT(CURRENT_DATE, '%y%m%d'),
        '-',
        LPAD(FLOOR(RAND() * 100000), 5, '0')
    );
    
    -- Create the citation
    INSERT INTO citations (
        citation_number,
        driver_id,
        vehicle_id,
        officer_id,
        violation_code,
        violation_date,
        violation_location,
        actual_fine_amount,
        notes
    ) VALUES (
        v_citation_num,
        v_driver_id,
        v_vehicle_id,
        p_officer_id,
        p_violation_code,
        p_violation_date,
        p_location,
        v_base_fine,
        p_notes
    );
    
    -- Add points to driver's license if applicable
    INSERT INTO driver_points (driver_id, citation_id, points_added, effective_date, expiration_date)
    SELECT 
        v_driver_id,
        LAST_INSERT_ID(),
        points_assigned,
        CURRENT_DATE,
        DATE_ADD(CURRENT_DATE, INTERVAL 2 YEAR)
    FROM 
        violation_types
    WHERE 
        violation_code = p_violation_code
        AND points_assigned > 0;
    
    SET p_citation_number = v_citation_num;
END //
DELIMITER ;

-- Defining the procedure to process a payment
DELIMITER //
CREATE PROCEDURE process_payment(
    IN p_citation_number VARCHAR(20),
    IN p_amount DECIMAL(10,2),
    IN p_method VARCHAR(20),
    IN p_reference VARCHAR(50),
    OUT p_payment_id INT)
BEGIN
    DECLARE v_citation_id INT;
    DECLARE v_citation_status VARCHAR(20);
    DECLARE v_amount_due DECIMAL(10,2);
    DECLARE v_payment_status VARCHAR(20);
    
    -- Get citation details
    SELECT citation_id, status, actual_fine_amount - IFNULL(SUM(amount), 0)
    INTO v_citation_id, v_citation_status, v_amount_due
    FROM citations
    LEFT JOIN payments ON citations.citation_id = payments.citation_id
    WHERE citation_number = p_citation_number
    GROUP BY citation_id;
    
    IF v_citation_id IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Citation not found';
    END IF;
    
    -- Check if citation can be paid
    IF v_citation_status NOT IN ('issued', 'disputed') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Citation cannot be paid in its current status';
    END IF;
    
    -- Check if payment covers amount due
    IF p_amount > v_amount_due THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Payment exceeds amount due';
    END IF;
    
    -- Record the payment
    INSERT INTO payments (
        citation_id,
        amount,
        payment_method,
        transaction_reference
    ) VALUES (
        v_citation_id,
        p_amount,
        p_method,
        p_reference
    );
    
    SET p_payment_id = LAST_INSERT_ID();
    
    -- Update citation status if fully paid
    IF p_amount = v_amount_due THEN
        UPDATE citations SET status = 'paid' WHERE citation_id = v_citation_id;
        
        -- Recall any active warrant for this citation
        UPDATE warrants SET status = 'recalled' 
        WHERE citation_id = v_citation_id AND status = 'active';
    END IF;
END //
DELIMITER ;

-- Defining the procedure to generate overdue citations report
DELIMITER //
CREATE PROCEDURE generate_overdue_report(
    IN p_days_overdue INT,
    IN p_include_warrants BOOLEAN)
BEGIN
    IF p_include_warrants THEN
        SELECT 
            c.citation_number,
            CONCAT(d.first_name, ' ', d.last_name) AS driver_name,
            d.license_number,
            c.violation_date,
            vt.description AS violation,
            c.actual_fine_amount - IFNULL(SUM(p.amount), 0) AS amount_due,
            DATEDIFF(CURRENT_DATE, c.issued_date) AS days_overdue,
            CASE WHEN c.status = 'warrant' THEN 'YES' ELSE 'NO' END AS warrant_issued
        FROM 
            citations c
        JOIN 
            drivers d ON c.driver_id = d.driver_id
        JOIN 
            violation_types vt ON c.violation_code = vt.violation_code
        LEFT JOIN 
            payments p ON c.citation_id = p.citation_id
        WHERE 
            (c.status = 'issued' OR c.status = 'warrant')
            AND DATEDIFF(CURRENT_DATE, c.issued_date) >= p_days_overdue
        GROUP BY 
            c.citation_id
        ORDER BY 
            days_overdue DESC;
    ELSE
        SELECT 
            c.citation_number,
            CONCAT(d.first_name, ' ', d.last_name) AS driver_name,
            d.license_number,
            c.violation_date,
            vt.description AS violation,
            c.actual_fine_amount - IFNULL(SUM(p.amount), 0) AS amount_due,
            DATEDIFF(CURRENT_DATE, c.issued_date) AS days_overdue
        FROM 
            citations c
        JOIN 
            drivers d ON c.driver_id = d.driver_id
        JOIN 
            violation_types vt ON c.violation_code = vt.violation_code
        LEFT JOIN 
            payments p ON c.citation_id = p.citation_id
        WHERE 
            c.status = 'issued'
            AND DATEDIFF(CURRENT_DATE, c.issued_date) >= p_days_overdue
        GROUP BY 
            c.citation_id
        ORDER BY 
            days_overdue DESC;
    END IF;
END //
DELIMITER ;

-- Creating a trigger to update citation status when fully paid
DELIMITER //
CREATE TRIGGER update_citation_status_after_payment
AFTER INSERT ON payments
FOR EACH ROW
BEGIN
    DECLARE v_total_paid DECIMAL(10,2);
    DECLARE v_fine_amount DECIMAL(10,2);
    
    SELECT SUM(amount) INTO v_total_paid 
    FROM payments 
    WHERE citation_id = NEW.citation_id;
    
    SELECT actual_fine_amount INTO v_fine_amount 
    FROM citations 
    WHERE citation_id = NEW.citation_id;
    
    IF v_total_paid >= v_fine_amount THEN
        UPDATE citations 
        SET status = 'paid' 
        WHERE citation_id = NEW.citation_id;
    END IF;
END //
DELIMITER ;

-- Creating a trigger to create warrant for overdue citations
DELIMITER //
CREATE TRIGGER create_warrant_for_overdue
AFTER UPDATE ON citations
FOR EACH ROW
BEGIN
    DECLARE v_days_overdue INT;
    DECLARE v_amount_due DECIMAL(10,2);
    
    IF NEW.status = 'issued' AND OLD.status = 'issued' THEN
        SET v_days_overdue = DATEDIFF(CURRENT_DATE, NEW.issued_date);
        
        IF v_days_overdue >= 90 THEN
            SELECT NEW.actual_fine_amount - IFNULL(SUM(amount), 0) INTO v_amount_due
            FROM payments
            WHERE citation_id = NEW.citation_id;
            
            IF v_amount_due > 0 THEN
                INSERT INTO warrants (citation_id, amount_due)
                VALUES (NEW.citation_id, v_amount_due);
                
                UPDATE citations SET status = 'warrant' WHERE citation_id = NEW.citation_id;
            END IF;
        END IF;
    END IF;
END //
DELIMITER ;

-- Creating a trigger to validate officer status when issuing citations
DELIMITER //
CREATE TRIGGER validate_officer_status
BEFORE INSERT ON citations
FOR EACH ROW
BEGIN
    DECLARE v_officer_active BOOLEAN;
    
    SELECT active_status INTO v_officer_active
    FROM officers
    WHERE officer_id = NEW.officer_id;
    
    IF NOT v_officer_active THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Cannot issue citation with inactive officer';
    END IF;
END //
DELIMITER ;

-- INSERTING SOME SAMPLE DATA 
-- Insert sample violation types
INSERT INTO violation_types (violation_code, description, base_fine_amount, is_moving_violation, points_assigned) VALUES
('SPD10', 'Speeding 1-10 kph over limit', 1250.00, TRUE, 2),
('SPD20', 'Speeding 11-20 kph over limit', 2000.00, TRUE, 4),
('STPL', 'Failure to stop at stop sign', 1500.00, TRUE, 3),
('RLR', 'Running red light', 2500.00, TRUE, 4),
('NOL', 'No valid license', 3000.00, FALSE, 0),
('NOV', 'No valid registration', 1000.00, FALSE, 0),
('NOP', 'No proof of insurance', 2000.00, FALSE, 0),
('DUI', 'Driving under influence', 10000.00, TRUE, 8);

-- Insert sample officers
INSERT INTO officers (badge_number, first_name, last_name, department, officer_rank, hire_date) VALUES
('PD-1234', 'Michael', 'Munene', 'Traffic Division', 'Sergeant', '2015-06-15'),
('PD-5678', 'Sarah', 'Chelimo', 'Traffic Division', 'Officer', '2018-03-22'),
('PD-9012', 'Robert', 'Odhiambo', 'Patrol Division', 'Officer', '2019-11-05');

-- Insert sample drivers
INSERT INTO drivers (license_number, first_name, last_name, date_of_birth, address, city, state, zip_code, phone, license_issue_date, license_expiry_date, license_class) VALUES
('DL-12345678', 'John', 'Muli', '1985-07-15', '123 Main St', 'Springfield', 'IL', '62704', '555-123-4567', '2020-01-15', '2025-01-15', 'D'),
('DL-87654321', 'Emily', 'Gakii', '1990-11-22', '456 Oak Ave', 'Springfield', 'IL', '62704', '555-234-5678', '2019-05-20', '2024-05-20', 'D'),
('DL-13579246', 'David', 'Mwite', '1978-03-08', '789 Pine Rd', 'Springfield', 'IL', '62704', '555-345-6789', '2021-02-10', '2026-02-10', 'D');

-- Insert sample vehicles
INSERT INTO vehicles (vin, license_plate, make, model, year, color, registered_owner_id, registration_expiry, insurance_policy_number, insurance_expiry) VALUES
('1HGCM82633A123456', 'KCC-123K', 'Honda', 'Accord', 2020, 'Blue', 1, '2023-12-31', 'INS-987654', '2023-06-30'),
('5XYZH4AG4DH123456', 'KBZ-567N', 'Toyota', 'Camry', 2018, 'Red', 2, '2023-11-30', 'INS-876543', '2023-05-31'),
('2G1WF52E359123456', 'KBF-901D', 'Chevrolet', 'Impala', 2019, 'Black', 3, '2024-01-31', 'INS-765432', '2023-07-31');

-- Insert sample citations
CALL issue_citation('DL-12345678', 'KCC-123K', 1, 'SPD10', '2023-01-15 14:30:00', 'Main St & 5th Ave', 'Driver was speeding in school zone', @citation1);
CALL issue_citation('DL-87654321', 'KBZ-567N', 2, 'STPL', '2023-01-16 09:15:00', 'Oak Ave & Maple St', 'Rolled through stop sign', @citation2);
CALL issue_citation('DL-13579246', 'KBF-901D', 1, 'RLR', '2023-01-17 16:45:00', 'Pine Rd & Elm St', 'Ran red light, nearly caused accident', @citation3);

