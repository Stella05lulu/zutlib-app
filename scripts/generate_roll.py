"""Generate a realistic ZUT student roll for development and demonstration.

No real student records are used. Numbers follow the institution's format
so that the administrator import path can be tested as it would be used.

    python scripts/generate_roll.py > roll.csv
"""
import csv, random, sys

random.seed(2300339)

SURNAMES = [
    "Banda","Phiri","Mwanza","Tembo","Zulu","Sakala","Chanda","Mulenga","Daka",
    "Lungu","Mbewe","Nyirenda","Kabwe","Musonda","Simukonda","Chileshe","Bwalya",
    "Kunda","Mumba","Ngoma","Sinyangwe","Chibale","Mutale","Kalaba","Sichone",
    "Kapambwe","Namonje","Chola","Lubinda","Mweemba","Hamoonga","Muyunda",
]
FIRST = [
    "Chanda","Mutale","Natasha","Brian","Mwila","Chipo","Kondwani","Thandiwe",
    "Mapalo","Bwalya","Lweendo","Musonda","Chileshe","Nkonde","Temwani","Lushomo",
    "Kasuba","Mwaka","Sepo","Chimwemwe","Taonga","Mulenga","Kabwe","Lombe",
]
PROGRAMMES = [
    ("Bachelor of Information Technology", "ICT"),
    ("Bachelor of Computer Science", "ICT"),
    ("Telecommunications and Networks Engineering", "ICT"),
    ("Bachelor of Business Administration", "Business"),
    ("Bachelor of Civil Engineering", "Engineering"),
    ("Bachelor of Electrical Engineering", "Engineering"),
]

def build(n=60):
    rows, used = [], set()
    for _ in range(n):
        year = random.choice([21, 22, 23, 24])
        while True:
            num = f"{year}{random.randint(10000, 99999)}"
            if num not in used:
                used.add(num); break
        prog, dept = random.choice(PROGRAMMES)
        rows.append({
            "student_number": num,
            "surname": random.choice(SURNAMES),
            "first_name": random.choice(FIRST),
            "programme": prog,
            "department": dept,
            "intake_year": 2000 + year,
        })

    # Known accounts for the demonstration.
    rows[0].update(student_number="2300339", surname="Namonje",
                   first_name="Stella", programme="Bachelor of Information Technology",
                   department="ICT", intake_year=2023)
    rows[1].update(student_number="2300340", surname="Banda", first_name="Joseph",
                   programme="Bachelor of Information Technology",
                   department="ICT", intake_year=2023)

    # Two records that exist to be refused on stage.
    rows[2].update(student_number="2100001", surname="Mwanza", first_name="Grace")
    rows[3].update(student_number="2100002", surname="Phiri",  first_name="Daniel")
    return rows

if __name__ == "__main__":
    rows = build()
    out = csv.DictWriter(sys.stdout, fieldnames=list(rows[0].keys()))
    out.writeheader(); out.writerows(rows)
