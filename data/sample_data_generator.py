"""
Sample Data Generator — Retail E-Commerce Example
==================================================

Example data generator for the retail demo included in this repo.
Replace with your own data for a different domain.

Generates 8 CSV files with realistic Indian e-commerce data:
  - customers.csv          (5,000 rows)  → Snowflake table (Cortex Analyst)
  - products.csv           (5,000 rows)  → Snowflake table (Cortex Analyst)
  - transactions.csv       (10,000 rows) → Snowflake table (Cortex Analyst)
  - customer_events.csv    (5,000 rows)  → Snowflake table (Cortex Analyst)
  - reviews.csv            (5,000 rows)  → Snowflake table (Cortex Search)
  - support_tickets.csv    (5,000 rows)  → Snowflake table (Cortex Search)
  - marketing_campaigns.csv       (500 rows) → S3/Bedrock KB (generic tool)
  - competitor_intelligence.csv   (500 rows) → S3/Bedrock KB (generic tool)

Usage:
    python sample_data_generator.py

Output:
    All CSVs written to the current directory.
    Uses only Python stdlib (csv, json, random, datetime) — no pip install needed.
"""

import csv
import json
import random
from datetime import datetime, timedelta
from pathlib import Path

# Seed for reproducibility
random.seed(42)

# ============================================================================
# CONSTANTS - Indian e-commerce domain data
# ============================================================================

STATES = [
    "Maharashtra", "Karnataka", "Tamil Nadu", "Delhi", "Uttar Pradesh",
    "Gujarat", "Rajasthan", "West Bengal", "Telangana", "Kerala",
    "Madhya Pradesh", "Punjab", "Haryana", "Bihar", "Odisha"
]

CITIES_BY_STATE = {
    "Maharashtra": ["Mumbai", "Pune", "Nagpur", "Nashik", "Thane"],
    "Karnataka": ["Bangalore", "Mysore", "Hubli", "Mangalore", "Belgaum"],
    "Tamil Nadu": ["Chennai", "Coimbatore", "Madurai", "Salem", "Trichy"],
    "Delhi": ["New Delhi", "Dwarka", "Rohini", "Karol Bagh", "Saket"],
    "Uttar Pradesh": ["Lucknow", "Noida", "Agra", "Varanasi", "Kanpur"],
    "Gujarat": ["Ahmedabad", "Surat", "Vadodara", "Rajkot", "Gandhinagar"],
    "Rajasthan": ["Jaipur", "Jodhpur", "Udaipur", "Kota", "Ajmer"],
    "West Bengal": ["Kolkata", "Howrah", "Siliguri", "Durgapur", "Asansol"],
    "Telangana": ["Hyderabad", "Warangal", "Nizamabad", "Karimnagar", "Khammam"],
    "Kerala": ["Kochi", "Thiruvananthapuram", "Kozhikode", "Thrissur", "Kollam"],
    "Madhya Pradesh": ["Bhopal", "Indore", "Gwalior", "Jabalpur", "Ujjain"],
    "Punjab": ["Chandigarh", "Ludhiana", "Amritsar", "Jalandhar", "Patiala"],
    "Haryana": ["Gurgaon", "Faridabad", "Panipat", "Ambala", "Karnal"],
    "Bihar": ["Patna", "Gaya", "Muzaffarpur", "Bhagalpur", "Darbhanga"],
    "Odisha": ["Bhubaneswar", "Cuttack", "Rourkela", "Berhampur", "Sambalpur"],
}

CATEGORIES = {
    "Electronics": ["Smartphones", "Laptops", "Tablets", "Headphones", "Smartwatches", "Cameras"],
    "Fashion": ["Men Clothing", "Women Clothing", "Footwear", "Accessories", "Kids Wear"],
    "Home & Kitchen": ["Appliances", "Cookware", "Furniture", "Decor", "Gardening"],
    "Grocery": ["Staples", "Snacks", "Beverages", "Dairy", "Personal Care"],
    "Sports & Fitness": ["Gym Equipment", "Sportswear", "Outdoor Gear", "Supplements", "Yoga"],
    "Books": ["Fiction", "Non-Fiction", "Academic", "Comics", "Self-Help"],
}

BRANDS = [
    "Samsung", "Apple", "Xiaomi", "OnePlus", "Boat", "Sony", "LG", "HP",
    "Nike", "Adidas", "Puma", "Levi's", "Allen Solly", "Peter England",
    "Prestige", "Bajaj", "Godrej", "Tata", "ITC", "Amul", "Dabur",
    "Woodland", "Bata", "Fastrack", "Titan", "Decathlon"
]

CUSTOMER_SEGMENTS = ["Premium", "Regular", "Budget", "Loyalty Plus", "New", "VIP"]
GENDERS = ["Male", "Female"]
STATUSES = ["Active", "Inactive"]
ORDER_STATUSES = ["Delivered", "Shipped", "Pending", "Cancelled", "Returned"]
PAYMENT_METHODS = ["UPI", "Credit Card", "Debit Card", "Net Banking", "COD", "Wallet"]
CHANNELS = ["Mobile App", "Desktop Website", "Mobile Website"]
STOCK_STATUSES = ["In Stock", "Out of Stock", "Limited Stock"]
SHIPPING_TYPES = ["Standard", "Express", "Free", "Same Day"]
EVENT_TYPES = [
    "page_view", "product_view", "add_to_cart", "remove_from_cart",
    "wishlist_add", "search", "checkout_start", "checkout_complete",
    "login", "logout", "review_submit", "support_ticket", "app_open"
]
ISSUE_CATEGORIES = [
    "Product Quality", "Delivery Issue", "Payment Problem", "Return/Refund",
    "Wrong Product", "Missing Item", "Technical Issue", "Account Issue"
]
PRIORITIES = ["Low", "Medium", "High", "Critical"]
TICKET_STATUSES = ["Open", "In Progress", "Resolved", "Closed", "Escalated"]
COMPETITORS = [
    "Amazon India", "Flipkart", "Myntra", "Croma", "BigBasket",
    "JioMart", "Nykaa", "Tata CLiQ", "Reliance Digital", "Decathlon India"
]
MARKETING_CHANNELS = [
    "Google Search", "Instagram", "Facebook", "YouTube", "WhatsApp",
    "Email", "LinkedIn", "Twitter/X", "SMS"
]
CAMPAIGN_TYPES = [
    "Display Ads", "Search Ads", "Influencer", "WhatsApp", "Email Campaign",
    "Social Media", "Video Ads", "Retargeting", "Flash Sale", "Seasonal"
]

FIRST_NAMES_MALE = ["Aarav", "Vihaan", "Aditya", "Sai", "Arjun", "Vivaan", "Reyansh", "Krishna", "Ishaan", "Shaurya",
                     "Rahul", "Amit", "Raj", "Vikram", "Suresh", "Deepak", "Manoj", "Karan", "Rohan", "Nikhil"]
FIRST_NAMES_FEMALE = ["Aadhya", "Saanvi", "Ananya", "Ishita", "Diya", "Priya", "Neha", "Pooja", "Shreya", "Kavya",
                       "Riya", "Megha", "Tanvi", "Swati", "Nisha", "Divya", "Anjali", "Sneha", "Sakshi", "Kriti"]
LAST_NAMES = ["Sharma", "Patel", "Singh", "Kumar", "Verma", "Gupta", "Reddy", "Nair", "Iyer", "Joshi",
              "Mehta", "Das", "Rao", "Mishra", "Shah", "Agarwal", "Chatterjee", "Pillai", "Menon", "Bhat"]

REVIEW_TEMPLATES_POSITIVE = [
    "Great product, very happy with the quality!",
    "Excellent value for money. Highly recommend!",
    "Delivery was fast and packaging was good.",
    "Product exactly as described. Love it!",
    "Best purchase I made this year. Amazing quality.",
    "Very satisfied with this purchase. Will buy again.",
    "Premium quality product. Worth every rupee.",
    "Fantastic product, exceeded my expectations!",
]
REVIEW_TEMPLATES_NEGATIVE = [
    "Poor quality, not worth the price.",
    "Delivery was delayed by a week. Very disappointed.",
    "Product arrived damaged. Need replacement.",
    "Not as shown in the pictures. Misleading.",
    "Terrible customer support experience.",
    "Product stopped working after 2 days.",
    "Worst purchase ever. Complete waste of money.",
    "Quality is below average. Expected much better.",
]
REVIEW_TEMPLATES_NEUTRAL = [
    "Average product. Nothing special.",
    "Decent quality for the price range.",
    "Okay product, could be better.",
    "Product is fine but delivery was slow.",
]

RESOLUTION_TEMPLATES = [
    "Replacement sent. Customer satisfied.",
    "Full refund processed successfully.",
    "Issue resolved after troubleshooting with customer.",
    "Escalated to technical team. Fix applied.",
    "Partial refund issued as goodwill gesture.",
    "Customer guided through setup process.",
    "Delivery rescheduled. Package delivered.",
    "Credit applied to customer account.",
]


def random_date(start_year=2025, end_year=2026):
    start = datetime(start_year, 1, 1)
    end = datetime(end_year, 4, 15)
    delta = end - start
    return start + timedelta(days=random.randint(0, delta.days))


def random_dob():
    start = datetime(1970, 1, 1)
    end = datetime(2005, 1, 1)
    delta = end - start
    return start + timedelta(days=random.randint(0, delta.days))


def write_csv(filepath, headers, rows):
    with open(filepath, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(headers)
        writer.writerows(rows)
    print(f"  Written: {filepath} ({len(rows)} rows)")


# ============================================================================
# GENERATE CUSTOMERS
# ============================================================================
def generate_customers(n=5000):
    rows = []
    for i in range(1, n + 1):
        gender = random.choice(GENDERS)
        first = random.choice(FIRST_NAMES_MALE if gender == "Male" else FIRST_NAMES_FEMALE)
        last = random.choice(LAST_NAMES)
        state = random.choice(STATES)
        city = random.choice(CITIES_BY_STATE[state])
        reg_date = random_date(2023, 2026)
        dob = random_dob()
        rows.append([
            f"CUS-{i:05d}",
            first,
            last,
            f"{first} {last}",
            gender,
            dob.strftime("%Y-%m-%d"),
            f"{first.lower()}.{last.lower()}{random.randint(1,999)}@{'gmail.com' if random.random() > 0.3 else 'yahoo.com'}",
            f"+91{random.randint(7000000000, 9999999999)}",
            state,
            city,
            random.choice(CUSTOMER_SEGMENTS),
            reg_date.strftime("%Y-%m-%d"),
            random.choice(STATUSES),
        ])
    headers = ["CUSTOMER_ID", "FIRST_NAME", "LAST_NAME", "FULL_NAME", "GENDER",
               "DATE_OF_BIRTH", "EMAIL", "PHONE", "STATE", "CITY",
               "CUSTOMER_SEGMENT", "REGISTRATION_DATE", "STATUS"]
    return headers, rows


# ============================================================================
# GENERATE PRODUCTS
# ============================================================================
def generate_products(n=5000):
    rows = []
    for i in range(1, n + 1):
        cat = random.choice(list(CATEGORIES.keys()))
        sub_cat = random.choice(CATEGORIES[cat])
        brand = random.choice(BRANDS)
        price = round(random.uniform(99, 49999), 2)
        rating = round(random.uniform(1.0, 5.0), 1)
        rows.append([
            f"PRD-{i:05d}",
            f"{brand} {sub_cat} - Model {random.randint(100,9999)}",
            cat,
            sub_cat,
            brand,
            price,
            rating,
            random.choice(STOCK_STATUSES),
            random.choice(SHIPPING_TYPES),
            random.randint(0, 500),
        ])
    headers = ["PRODUCT_ID", "PRODUCT_NAME", "CATEGORY", "SUB_CATEGORY", "BRAND",
               "PRICE_INR", "RATING", "STOCK_STATUS", "SHIPPING_TYPE", "INVENTORY_COUNT"]
    return headers, rows


# ============================================================================
# GENERATE TRANSACTIONS
# ============================================================================
def generate_transactions(n=10000, num_customers=5000, num_products=5000):
    rows = []
    for i in range(1, n + 1):
        cid = f"CUS-{random.randint(1, num_customers):05d}"
        pid = f"PRD-{random.randint(1, num_products):05d}"
        qty = random.randint(1, 5)
        unit_price = round(random.uniform(99, 25000), 2)
        discount = random.choice([0, 0, 0, 5, 10, 15, 20, 25, 30])
        total = round(qty * unit_price * (1 - discount / 100), 2)
        rows.append([
            f"TXN-{i:05d}",
            cid,
            pid,
            random_date().strftime("%Y-%m-%d"),
            qty,
            unit_price,
            total,
            random.choice(ORDER_STATUSES),
            random.choice(PAYMENT_METHODS),
            random.choice(CHANNELS),
            discount,
        ])
    headers = ["TRANSACTION_ID", "CUSTOMER_ID", "PRODUCT_ID", "TRANSACTION_DATE",
               "QUANTITY", "UNIT_PRICE", "TOTAL_AMOUNT", "ORDER_STATUS",
               "PAYMENT_METHOD", "CHANNEL", "DISCOUNT_PERCENT"]
    return headers, rows


# ============================================================================
# GENERATE CUSTOMER EVENTS
# ============================================================================
def generate_customer_events(n=5000, num_customers=5000):
    rows = []
    for i in range(1, n + 1):
        cid = f"CUS-{random.randint(1, num_customers):05d}"
        evt_type = random.choice(EVENT_TYPES)
        ts = random_date()
        ts_str = ts.strftime("%Y-%m-%d") + f" {random.randint(0,23):02d}:{random.randint(0,59):02d}:{random.randint(0,59):02d}"
        event_data = json.dumps({
            "page": f"/{evt_type.replace('_', '-')}",
            "device": random.choice(["mobile", "desktop", "tablet"]),
            "session_id": f"sess-{random.randint(100000,999999)}",
        })
        rows.append([
            f"EVT-{i:05d}",
            cid,
            ts_str,
            evt_type,
            event_data,
        ])
    headers = ["EVENT_ID", "CUSTOMER_ID", "EVENT_TIMESTAMP", "EVENT_TYPE", "EVENT_DATA"]
    return headers, rows


# ============================================================================
# GENERATE REVIEWS
# ============================================================================
def generate_reviews(n=5000, num_products=5000, num_customers=5000):
    rows = []
    for i in range(1, n + 1):
        rating = random.choices([1, 2, 3, 4, 5], weights=[5, 10, 15, 35, 35])[0]
        if rating >= 4:
            text = random.choice(REVIEW_TEMPLATES_POSITIVE)
        elif rating <= 2:
            text = random.choice(REVIEW_TEMPLATES_NEGATIVE)
        else:
            text = random.choice(REVIEW_TEMPLATES_NEUTRAL)
        rows.append([
            f"REV-{i:05d}",
            f"PRD-{random.randint(1, num_products):05d}",
            f"CUS-{random.randint(1, num_customers):05d}",
            random_date().strftime("%Y-%m-%d"),
            rating,
            text,
        ])
    headers = ["REVIEW_ID", "PRODUCT_ID", "CUSTOMER_ID", "REVIEW_DATE", "RATING", "REVIEW_TEXT"]
    return headers, rows


# ============================================================================
# GENERATE SUPPORT TICKETS
# ============================================================================
def generate_support_tickets(n=5000, num_products=5000, num_customers=5000):
    rows = []
    issue_templates = {
        "Product Quality": "Product {pid} has quality issues - {detail}",
        "Delivery Issue": "Order delivery for {pid} was {detail}",
        "Payment Problem": "Payment for order containing {pid} - {detail}",
        "Return/Refund": "Return request for {pid} - {detail}",
        "Wrong Product": "Received wrong product instead of {pid} - {detail}",
        "Missing Item": "Item {pid} missing from order - {detail}",
        "Technical Issue": "Technical problem with {pid} - {detail}",
        "Account Issue": "Account issue related to order with {pid} - {detail}",
    }
    details = ["not working properly", "damaged on arrival", "delayed significantly",
               "failed to process", "doesn't match description", "needs immediate attention",
               "customer is unhappy", "requires escalation"]
    for i in range(1, n + 1):
        pid = f"PRD-{random.randint(1, num_products):05d}"
        issue_cat = random.choice(ISSUE_CATEGORIES)
        status = random.choice(TICKET_STATUSES)
        template = issue_templates[issue_cat]
        desc = template.format(pid=pid, detail=random.choice(details))
        resolution = random.choice(RESOLUTION_TEMPLATES) if status in ["Resolved", "Closed"] else ""
        rows.append([
            f"TKT-{i:05d}",
            f"CUS-{random.randint(1, num_customers):05d}",
            pid,
            random_date().strftime("%Y-%m-%d"),
            issue_cat,
            random.choice(PRIORITIES),
            status,
            desc,
            resolution,
            random.randint(1, 72) if status in ["Resolved", "Closed"] else 0,
            random.randint(1, 5) if status in ["Resolved", "Closed"] else 0,
        ])
    headers = ["TICKET_ID", "CUSTOMER_ID", "PRODUCT_ID", "CREATED_DATE",
               "ISSUE_CATEGORY", "PRIORITY", "TICKET_STATUS",
               "ISSUE_DESCRIPTION", "RESOLUTION_NOTES", "RESOLUTION_HOURS", "CSAT_SCORE"]
    return headers, rows


# ============================================================================
# GENERATE MARKETING CAMPAIGNS (for S3 → Bedrock KB)
# ============================================================================
def generate_marketing_campaigns(n=500, num_products=5000):
    campaign_name_templates = [
        "Brand Day - {sub_cat} {year}", "Weekend Flash Sale - {sub_cat} {year}",
        "Premium Collection - {sub_cat} {year}", "Festive Season - {sub_cat} {year}",
        "Diwali Special - {sub_cat} {year}", "Republic Day - {sub_cat} {year}",
        "Eid Celebration - {sub_cat} {year}", "Summer Sale - {sub_cat} {year}",
        "Back to School - {sub_cat} {year}", "New Year Offer - {sub_cat} {year}",
        "Clearance Sale - {sub_cat} {year}", "Loyalty Rewards - {sub_cat} {year}",
    ]
    rows = []
    for i in range(1, n + 1):
        cat = random.choice(list(CATEGORIES.keys()))
        sub_cat = random.choice(CATEGORIES[cat])
        channel = random.choice(MARKETING_CHANNELS)
        camp_type = random.choice(CAMPAIGN_TYPES)
        start = random_date()
        end = start + timedelta(days=random.randint(5, 30))
        budget = round(random.uniform(10000, 500000), 2)
        spend = round(budget * random.uniform(0.6, 1.0), 2)
        impressions = random.randint(100000, 5000000)
        clicks = int(impressions * random.uniform(0.005, 0.08))
        conversions = int(clicks * random.uniform(0.02, 0.10))
        ctr = round(clicks / impressions * 100, 2) if impressions > 0 else 0
        conv_rate = round(conversions / clicks * 100, 2) if clicks > 0 else 0
        cpa = round(spend / conversions, 2) if conversions > 0 else 0
        roi = round((conversions * random.uniform(500, 5000) - spend) / spend * 100, 1) if spend > 0 else 0
        year = random.choice([2025, 2026])
        name = random.choice(campaign_name_templates).format(sub_cat=sub_cat, year=year)
        rows.append([
            f"CMP-{i:05d}",
            name,
            camp_type,
            channel,
            start.strftime("%Y-%m-%d"),
            end.strftime("%Y-%m-%d"),
            budget,
            spend,
            impressions,
            clicks,
            conversions,
            random.choice(CUSTOMER_SEGMENTS),
            cat,
            sub_cat,
            f"PRD-{random.randint(1, num_products):05d}",
            random.choice(STATES),
            ctr,
            conv_rate,
            cpa,
            roi,
        ])
    headers = ["CAMPAIGN_ID", "CAMPAIGN_NAME", "CAMPAIGN_TYPE", "CHANNEL",
               "START_DATE", "END_DATE", "BUDGET_INR", "SPEND_INR",
               "IMPRESSIONS", "CLICKS", "CONVERSIONS", "TARGET_SEGMENT",
               "TARGET_CATEGORY", "TARGET_SUB_CATEGORY", "PRODUCT_ID", "REGION",
               "CTR", "CONVERSION_RATE", "COST_PER_ACQUISITION_INR", "ROI_PERCENT"]
    return headers, rows


# ============================================================================
# GENERATE COMPETITOR INTELLIGENCE (for S3 → Bedrock KB)
# ============================================================================
def generate_competitor_intelligence(n=500, num_products=5000):
    rows = []
    for i in range(1, n + 1):
        competitor = random.choice(COMPETITORS)
        cat = random.choice(list(CATEGORIES.keys()))
        sub_cat = random.choice(CATEGORIES[cat])
        brand = random.choice(BRANDS)
        our_price = round(random.uniform(200, 30000), 2)
        price_diff_pct = random.uniform(-30, 40)
        comp_price = round(our_price * (1 - price_diff_pct / 100), 2)
        price_diff = round(our_price - comp_price, 2)
        rows.append([
            f"COMP-{i:05d}",
            competitor,
            f"{competitor} {sub_cat} - {brand} Alternative",
            cat,
            sub_cat,
            brand,
            comp_price,
            f"PRD-{random.randint(1, num_products):05d}",
            our_price,
            price_diff,
            round(price_diff_pct, 1),
            round(random.uniform(1.5, 5.0), 1),
            random.randint(500, 25000),
            round(random.uniform(1.0, 30.0), 1),
            random.choice(STOCK_STATUSES),
            random_date().strftime("%Y-%m-%d"),
            random.randint(1, 7),
            random.choice(["30-day easy return", "15-day return policy",
                          "10-day return for defective items only", "7-day easy return",
                          "No return policy"]),
            random.choice(["Rising", "Falling", "Stable"]),
        ])
    headers = ["COMPETITOR_ID", "COMPETITOR_NAME", "COMPETITOR_PRODUCT_NAME",
               "CATEGORY", "SUB_CATEGORY", "BRAND", "COMPETITOR_PRICE_INR",
               "OUR_PRODUCT_ID", "OUR_PRICE_INR", "PRICE_DIFFERENCE_INR",
               "PRICE_DIFFERENCE_PCT", "COMPETITOR_RATING", "COMPETITOR_REVIEW_COUNT",
               "MARKET_SHARE_PCT", "COMPETITOR_STOCK_STATUS", "LAST_UPDATED",
               "COMPETITOR_DELIVERY_DAYS", "COMPETITOR_RETURN_POLICY", "PRICE_TREND"]
    return headers, rows


# ============================================================================
# MAIN
# ============================================================================
if __name__ == "__main__":
    output_dir = Path(".")
    print("Retail Intelligence Agent - Sample Data Generator")
    print("=" * 50)

    generators = [
        ("customers.csv", generate_customers),
        ("products.csv", generate_products),
        ("transactions.csv", generate_transactions),
        ("customer_events.csv", generate_customer_events),
        ("reviews.csv", generate_reviews),
        ("support_tickets.csv", generate_support_tickets),
        ("marketing_campaigns.csv", generate_marketing_campaigns),
        ("competitor_intelligence.csv", generate_competitor_intelligence),
    ]

    for filename, gen_func in generators:
        headers, rows = gen_func()
        write_csv(output_dir / filename, headers, rows)

    print()
    print("All CSV files generated successfully!")
    print()
    print("Next steps:")
    print("  1. Upload customers.csv, products.csv, transactions.csv,")
    print("     customer_events.csv, reviews.csv, support_tickets.csv")
    print("     to Snowflake (via Snowsight UI or COPY INTO)")
    print()
    print("  2. Upload marketing_campaigns.csv and competitor_intelligence.csv")
    print("     to your S3 bucket for the Bedrock Knowledge Base")
