-- clinic_db.sql
-- Clinic Booking System (MySQL)
DROP DATABASE IF EXISTS clinic_db;
CREATE DATABASE clinic_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE clinic_db;

-- ------------------------------------------------------------------
-- Common ENUMs and small helper tables
-- ------------------------------------------------------------------
CREATE TABLE genders (
    gender_id TINYINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    code VARCHAR(10) NOT NULL UNIQUE,         -- e.g. 'male'/'female'
    label VARCHAR(20) NOT NULL
) ENGINE=InnoDB;

INSERT INTO genders (code,label) VALUES ('male','Male'),('female','Female'),('other','Other');

-- ------------------------------------------------------------------
-- Users (clinic staff / system users)
-- ------------------------------------------------------------------
CREATE TABLE users (
    user_id INT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    username VARCHAR(50) NOT NULL UNIQUE,
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(150) NOT NULL,
    role ENUM('admin','reception','nurse','doctor','lab','billing') NOT NULL DEFAULT 'reception',
    is_active TINYINT(1) NOT NULL DEFAULT 1,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- ------------------------------------------------------------------
-- Patients
-- ------------------------------------------------------------------
CREATE TABLE patients (
    patient_id INT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    gender_id TINYINT UNSIGNED,
    birth_date DATE,
    phone VARCHAR(30),
    email VARCHAR(255),
    address VARCHAR(500),
    national_id VARCHAR(100),               -- optional unique national id
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_patients_gender FOREIGN KEY (gender_id) REFERENCES genders(gender_id) ON DELETE SET NULL,
    UNIQUE (email)
) ENGINE=InnoDB;

-- ------------------------------------------------------------------
-- Insurance providers
-- ------------------------------------------------------------------
CREATE TABLE insurance_providers (
    provider_id INT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(200) NOT NULL UNIQUE,
    phone VARCHAR(50),
    address VARCHAR(400),
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE patient_insurances (
    patient_insurance_id INT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    patient_id INT UNSIGNED NOT NULL,
    provider_id INT UNSIGNED NOT NULL,
    policy_number VARCHAR(100) NOT NULL,
    valid_from DATE,
    valid_to DATE,
    is_primary TINYINT(1) NOT NULL DEFAULT 0,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_pi_patient FOREIGN KEY (patient_id) REFERENCES patients(patient_id) ON DELETE CASCADE,
    CONSTRAINT fk_pi_provider FOREIGN KEY (provider_id) REFERENCES insurance_providers(provider_id) ON DELETE CASCADE,
    UNIQUE (patient_id, provider_id, policy_number)
) ENGINE=InnoDB;

-- ------------------------------------------------------------------
-- Doctors and specialties (Many-to-Many)
-- ------------------------------------------------------------------
CREATE TABLE doctors (
    doctor_id INT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    user_id INT UNSIGNED,                     -- optional link to users table
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(255) UNIQUE,
    phone VARCHAR(30),
    license_number VARCHAR(100) NOT NULL UNIQUE,
    bio TEXT,
    is_active TINYINT(1) NOT NULL DEFAULT 1,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_doctor_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE specialties (
    specialty_id SMALLINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(150) NOT NULL UNIQUE,
    description TEXT
) ENGINE=InnoDB;

CREATE TABLE doctor_specialties (
    doctor_id INT UNSIGNED NOT NULL,
    specialty_id SMALLINT UNSIGNED NOT NULL,
    PRIMARY KEY (doctor_id, specialty_id),
    CONSTRAINT fk_ds_doctor FOREIGN KEY (doctor_id) REFERENCES doctors(doctor_id) ON DELETE CASCADE,
    CONSTRAINT fk_ds_specialty FOREIGN KEY (specialty_id) REFERENCES specialties(specialty_id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ------------------------------------------------------------------
-- Clinic Rooms (for in-person appointments, procedures)
-- ------------------------------------------------------------------
CREATE TABLE rooms (
    room_id SMALLINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    code VARCHAR(30) NOT NULL UNIQUE,
    name VARCHAR(150),
    location VARCHAR(255),
    capacity TINYINT UNSIGNED DEFAULT 1
) ENGINE=InnoDB;

-- ------------------------------------------------------------------
-- Clinic Services (consultation types, procedures) and pricing
-- ------------------------------------------------------------------
CREATE TABLE services (
    service_id INT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    code VARCHAR(50) NOT NULL UNIQUE,         -- e.g. 'CONS-30', 'XRAY'
    name VARCHAR(200) NOT NULL,
    description TEXT,
    duration_minutes SMALLINT UNSIGNED NOT NULL DEFAULT 30,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE service_pricing (
    pricing_id INT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    service_id INT UNSIGNED NOT NULL,
    price DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    currency CHAR(3) NOT NULL DEFAULT 'USD',
    effective_from DATE NOT NULL,
    effective_to DATE,
    CONSTRAINT fk_sp_service FOREIGN KEY (service_id) REFERENCES services(service_id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ------------------------------------------------------------------
-- Appointment table
-- ------------------------------------------------------------------
CREATE TABLE appointments (
    appointment_id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    patient_id INT UNSIGNED NOT NULL,
    doctor_id INT UNSIGNED NOT NULL,
    service_id INT UNSIGNED NOT NULL,
    room_id SMALLINT UNSIGNED,
    appointment_start DATETIME NOT NULL,
    appointment_end DATETIME NOT NULL,
    status ENUM('scheduled','confirmed','checked_in','in_progress','completed','cancelled','no_show') NOT NULL DEFAULT 'scheduled',
    reason TEXT,
    created_by_user_id INT UNSIGNED,    -- receptionist or system user who created booking
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_appt_patient FOREIGN KEY (patient_id) REFERENCES patients(patient_id) ON DELETE CASCADE,
    CONSTRAINT fk_appt_doctor FOREIGN KEY (doctor_id) REFERENCES doctors(doctor_id) ON DELETE RESTRICT,
    CONSTRAINT fk_appt_service FOREIGN KEY (service_id) REFERENCES services(service_id) ON DELETE RESTRICT,
    CONSTRAINT fk_appt_room FOREIGN KEY (room_id) REFERENCES rooms(room_id) ON DELETE SET NULL,
    CONSTRAINT fk_appt_creator FOREIGN KEY (created_by_user_id) REFERENCES users(user_id) ON DELETE SET NULL,
    INDEX idx_appt_doctor_start (doctor_id, appointment_start),
    INDEX idx_appt_patient_start (patient_id, appointment_start)
);

-- Optional uniqueness to reduce exact duplicate times for same doctor+start:
ALTER TABLE appointments
    ADD CONSTRAINT uniq_doctor_start UNIQUE (doctor_id, appointment_start);

-- ------------------------------------------------------------------
-- Appointments may have many services (M-N) -- link table
-- ------------------------------------------------------------------
CREATE TABLE appointment_services (
    appointment_service_id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    appointment_id BIGINT UNSIGNED NOT NULL,
    service_id INT UNSIGNED NOT NULL,
    qty SMALLINT UNSIGNED NOT NULL DEFAULT 1,
    price DECIMAL(10,2) DEFAULT NULL,
    CONSTRAINT fk_as_appointment FOREIGN KEY (appointment_id) REFERENCES appointments(appointment_id) ON DELETE CASCADE,
    CONSTRAINT fk_as_service FOREIGN KEY (service_id) REFERENCES services(service_id) ON DELETE RESTRICT,
    UNIQUE (appointment_id, service_id)
) ENGINE=InnoDB;

-- ------------------------------------------------------------------
-- Doctor availability / schedule (recurring or exceptions)
-- ------------------------------------------------------------------
CREATE TABLE doctor_availability (
    availability_id INT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    doctor_id INT UNSIGNED NOT NULL,
    day_of_week TINYINT UNSIGNED NOT NULL, -- 0=Sunday..6=Saturday
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    is_active TINYINT(1) NOT NULL DEFAULT 1,
    CONSTRAINT fk_da_doctor FOREIGN KEY (doctor_id) REFERENCES doctors(doctor_id) ON DELETE CASCADE,
    CHECK (start_time < end_time)
) ENGINE=InnoDB;

CREATE TABLE doctor_exceptions (
    exception_id INT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    doctor_id INT UNSIGNED NOT NULL,
    exception_date DATE NOT NULL,
    is_available TINYINT(1) NOT NULL DEFAULT 0, -- 0 = not available, 1 = available (override)
    notes VARCHAR(400),
    CONSTRAINT fk_de_doctor FOREIGN KEY (doctor_id) REFERENCES doctors(doctor_id) ON DELETE CASCADE,
    UNIQUE (doctor_id, exception_date)
) ENGINE=InnoDB;

-- ------------------------------------------------------------------
-- Medical records and notes
-- ------------------------------------------------------------------
CREATE TABLE medical_records (
    record_id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    patient_id INT UNSIGNED NOT NULL,
    created_by_user_id INT UNSIGNED,
    visit_date DATETIME NOT NULL,
    chief_complaint TEXT,
    history TEXT,
    assessment TEXT,
    plan TEXT,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_mr_patient FOREIGN KEY (patient_id) REFERENCES patients(patient_id) ON DELETE CASCADE,
    CONSTRAINT fk_mr_user FOREIGN KEY (created_by_user_id) REFERENCES users(user_id) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE appointment_notes (
    note_id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    appointment_id BIGINT UNSIGNED NOT NULL,
    user_id INT UNSIGNED NOT NULL,
    note_text TEXT NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_an_appointment FOREIGN KEY (appointment_id) REFERENCES appointments(appointment_id) ON DELETE CASCADE,
    CONSTRAINT fk_an_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE SET NULL
) ENGINE=InnoDB;

-- ------------------------------------------------------------------
-- Medications & Prescriptions
-- ------------------------------------------------------------------
CREATE TABLE medications (
    medication_id INT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(255) NOT NULL,
    generic_name VARCHAR(255),
    manufacturer VARCHAR(255),
    form VARCHAR(100),    -- e.g. tablet, syrup
    strength VARCHAR(100),-- e.g. 500 mg
    UNIQUE (name, strength)
) ENGINE=InnoDB;

CREATE TABLE prescriptions (
    prescription_id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    appointment_id BIGINT UNSIGNED,
    patient_id INT UNSIGNED NOT NULL,
    doctor_id INT UNSIGNED NOT NULL,
    issue_date DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    notes TEXT,
    CONSTRAINT fk_prescription_appointment FOREIGN KEY (appointment_id) REFERENCES appointments(appointment_id) ON DELETE SET NULL,
    CONSTRAINT fk_prescription_patient FOREIGN KEY (patient_id) REFERENCES patients(patient_id) ON DELETE CASCADE,
    CONSTRAINT fk_prescription_doctor FOREIGN KEY (doctor_id) REFERENCES doctors(doctor_id) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE prescription_items (
    prescription_item_id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    prescription_id BIGINT UNSIGNED NOT NULL,
    medication_id INT UNSIGNED NOT NULL,
    dosage VARCHAR(200),     -- e.g. "1 tablet twice daily"
    duration_days INT,
    instructions TEXT,
    qty_prescribed INT UNSIGNED,
    CONSTRAINT fk_pi_prescription FOREIGN KEY (prescription_id) REFERENCES prescriptions(prescription_id) ON DELETE CASCADE,
    CONSTRAINT fk_pi_medication FOREIGN KEY (medication_id) REFERENCES medications(medication_id) ON DELETE RESTRICT
) ENGINE=InnoDB;

-- ------------------------------------------------------------------
-- Lab tests and results
-- ------------------------------------------------------------------
CREATE TABLE lab_tests (
    lab_test_id INT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    code VARCHAR(80) NOT NULL UNIQUE,
    name VARCHAR(200) NOT NULL,
    description TEXT
) ENGINE=InnoDB;

CREATE TABLE test_orders (
    test_order_id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    appointment_id BIGINT UNSIGNED,
    patient_id INT UNSIGNED NOT NULL,
    ordered_by_doctor_id INT UNSIGNED,
    order_date DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status ENUM('ordered','in_lab','completed','cancelled') NOT NULL DEFAULT 'ordered',
    CONSTRAINT fk_to_appointment FOREIGN KEY (appointment_id) REFERENCES appointments(appointment_id) ON DELETE SET NULL,
    CONSTRAINT fk_to_patient FOREIGN KEY (patient_id) REFERENCES patients(patient_id) ON DELETE CASCADE,
    CONSTRAINT fk_to_doctor FOREIGN KEY (ordered_by_doctor_id) REFERENCES doctors(doctor_id) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE test_order_items (
    test_item_id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    test_order_id BIGINT UNSIGNED NOT NULL,
    lab_test_id INT UNSIGNED NOT NULL,
    qty SMALLINT UNSIGNED DEFAULT 1,
    CONSTRAINT fk_toi_order FOREIGN KEY (test_order_id) REFERENCES test_orders(test_order_id) ON DELETE CASCADE,
    CONSTRAINT fk_toi_test FOREIGN KEY (lab_test_id) REFERENCES lab_tests(lab_test_id) ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE test_results (
    test_result_id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    test_order_id BIGINT UNSIGNED NOT NULL,
    lab_test_id INT UNSIGNED NOT NULL,
    result_text TEXT,
    result_value VARCHAR(200),
    units VARCHAR(50),
    normal_range VARCHAR(100),
    reported_by_user_id INT UNSIGNED,
    reported_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_tr_order FOREIGN KEY (test_order_id) REFERENCES test_orders(test_order_id) ON DELETE CASCADE,
    CONSTRAINT fk_tr_test FOREIGN KEY (lab_test_id) REFERENCES lab_tests(lab_test_id) ON DELETE RESTRICT,
    CONSTRAINT fk_tr_user FOREIGN KEY (reported_by_user_id) REFERENCES users(user_id) ON DELETE SET NULL
) ENGINE=InnoDB;

-- Billing: invoices & payments

CREATE TABLE invoices (
    invoice_id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    patient_id INT UNSIGNED NOT NULL,
    appointment_id BIGINT UNSIGNED,
    invoice_date DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    total_amount DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    currency CHAR(3) NOT NULL DEFAULT 'USD',
    status ENUM('draft','issued','paid','partially_paid','void') NOT NULL DEFAULT 'issued',
    CONSTRAINT fk_inv_patient FOREIGN KEY (patient_id) REFERENCES patients(patient_id) ON DELETE CASCADE,
    CONSTRAINT fk_inv_appointment FOREIGN KEY (appointment_id) REFERENCES appointments(appointment_id) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE invoice_lines (
    line_id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    invoice_id BIGINT UNSIGNED NOT NULL,
    description VARCHAR(500) NOT NULL,
    qty INT UNSIGNED NOT NULL DEFAULT 1,
    unit_price DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    total_price DECIMAL(12,2) AS (qty * unit_price) STORED,
    CONSTRAINT fk_il_invoice FOREIGN KEY (invoice_id) REFERENCES invoices(invoice_id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE payments (
    payment_id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    invoice_id BIGINT UNSIGNED NOT NULL,
    amount DECIMAL(12,2) NOT NULL,
    payment_date DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    method ENUM('cash','card','insurance','mobile_money','bank_transfer') NOT NULL,
    reference VARCHAR(255),
    received_by_user_id INT UNSIGNED,
    CONSTRAINT fk_pay_invoice FOREIGN KEY (invoice_id) REFERENCES invoices(invoice_id) ON DELETE CASCADE,
    CONSTRAINT fk_pay_user FOREIGN KEY (received_by_user_id) REFERENCES users(user_id) ON DELETE SET NULL
) ENGINE=InnoDB;


-- Indexes for performance (on frequently queried columns)

CREATE INDEX idx_patients_name ON patients (last_name, first_name);
CREATE INDEX idx_doctors_name ON doctors (last_name, first_name);
CREATE INDEX idx_appointments_status ON appointments (status);


-- upcoming_appointments (optional convenience view)
DROP VIEW IF EXISTS upcoming_appointments;
CREATE VIEW upcoming_appointments AS
SELECT
    a.appointment_id,
    a.appointment_start,
    a.appointment_end,
    a.status,
    a.patient_id,
    p.first_name AS patient_first_name,
    p.last_name AS patient_last_name,
    a.doctor_id,
    d.first_name AS doctor_first_name,
    d.last_name AS doctor_last_name,
    s.name AS service_name,
    a.room_id
FROM appointments a
LEFT JOIN patients p ON a.patient_id = p.patient_id
LEFT JOIN doctors d ON a.doctor_id = d.doctor_id
LEFT JOIN services s ON a.service_id = s.service_id
WHERE a.appointment_start >= NOW();

