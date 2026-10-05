import Foundation

// The keyword lists of `CategoryClassifier`. Write each entry as a
// person would type it: entries are folded when the lists load, so
// "méditer" also matches "mediter" and "MÉDITER".
//
// Rules for new entries:
// - Generic words only, never a proper noun (a brand, a school).
// - The singular form: "professor" also matches "professors".
// - A word belongs to one category only, after folding. The tests check
//   this. Watch for French and English words that fold to the same
//   letters ("thèse" and "these").
// - Leave out words that are common in many contexts ("read", "test",
//   "date", "son"), because a wrong guess costs more than no guess.
extension CategoryClassifier {
    static let english: [ItemCategory: [String]] = [
        .fitness: [
            "run", "running", "jog", "jogging", "gym", "workout", "work out", "exercise",
            "cardio", "yoga", "pilates", "swim", "swimming", "bike", "biking", "cycling",
            "hike", "hiking", "walk", "walking", "stretch", "stretching", "squat", "pushup",
            "push ups", "sit ups", "plank", "marathon", "lift", "weightlifting", "treadmill",
            "climbing", "tennis", "football", "soccer", "basketball", "boxing", "sport",
            "fitness", "physical activity"
        ],
        .sleep: [
            "sleep", "asleep", "sleepy", "nap", "bed", "bedtime", "go to bed", "wake",
            "wake up", "alarm", "insomnia", "pillow", "snooze", "lights out", "siesta",
            "doze", "jet lag", "early night", "melatonin"
        ],
        .health: [
            "doctor", "dentist", "medicine", "medication", "meds", "pill", "vitamin",
            "supplement", "pharmacy", "prescription", "physio", "physiotherapy", "checkup",
            "blood test", "vaccine", "vaccination", "hospital", "clinic", "nurse", "water",
            "hydrate", "diet", "calorie", "floss", "teeth", "skincare", "sunscreen",
            "allergy", "health", "healthy", "vegetable", "veggie"
        ],
        .mind: [
            "meditate", "meditation", "mindfulness", "mindful", "breathe", "breathing",
            "breathwork", "journal", "journaling", "gratitude", "therapy", "therapist",
            "reflect", "reflection", "affirmation", "calm", "relax", "relaxation", "unplug",
            "digital detox", "pray", "prayer", "mood", "anxiety", "stress", "self care",
            "mental", "mental health", "reading", "read a book"
        ],
        .study: [
            "study", "studying", "homework", "exam", "quiz", "revise", "revision", "lecture",
            "class", "lesson", "professor", "teacher", "tutor", "school", "university",
            "college", "campus", "course", "coursework", "assignment", "essay", "thesis",
            "dissertation", "textbook", "syllabus", "semester", "flashcard", "vocabulary",
            "grammar", "math", "maths", "physics", "chemistry", "biology", "learn",
            "learning", "student", "degree", "scholarship", "seminar", "admission", "tutorial"
        ],
        .work: [
            "work", "meeting", "email", "slide", "presentation", "report", "deadline",
            "client", "customer", "project", "boss", "manager", "colleague", "coworker",
            "office", "interview", "proposal", "spreadsheet", "standup", "sprint",
            "conference", "agenda", "pitch", "job", "resume", "shift", "onboarding",
            "contract", "workshop", "roadmap", "code", "bug", "team"
        ],
        .money: [
            "pay", "rent", "bill", "budget", "bank", "tax", "invoice", "savings", "invest",
            "investment", "insurance", "loan", "mortgage", "debt", "credit card", "expense",
            "refund", "salary", "accountant", "finance", "pension", "subscription",
            "receipt", "payment", "money", "cash"
        ],
        .home: [
            "clean", "cleaning", "tidy", "laundry", "dish", "dishwasher", "vacuum", "mop",
            "dust", "kitchen", "bathroom", "garden", "gardening", "plant", "water the plants", "water plants",
            "cook", "cooking", "meal prep", "trash", "garbage", "recycling", "chore",
            "repair", "declutter", "ironing", "fridge", "oven", "window", "house", "home",
            "apartment", "furniture", "lawn", "mow"
        ],
        .errands: [
            "buy", "groceries", "grocery", "shopping", "shop", "store", "supermarket", "mall",
            "errand", "pick up", "drop off", "post office", "package", "parcel",
            "appointment", "haircut", "barber", "car wash", "gas", "fuel", "mechanic",
            "dry cleaning", "passport", "paperwork", "license", "renew"
        ],
        .social: [
            "call", "mom", "mum", "dad", "mother", "father", "parent", "family", "friend",
            "birthday", "party", "dinner", "lunch", "wedding", "visit", "grandma", "grandpa",
            "grandmother", "grandfather", "brother", "sister", "kid", "children", "daughter",
            "wife", "husband", "partner", "girlfriend", "boyfriend", "text", "message",
            "catch up", "hang out", "meet up", "gift", "anniversary", "neighbor", "invite"
        ],
        .creative: [
            "guitar", "piano", "violin", "drum", "ukulele", "instrument", "music", "song",
            "sing", "singing", "choir", "band", "draw", "drawing", "paint", "painting",
            "sketch", "write", "writing", "novel", "poem", "poetry", "photo", "photography",
            "film", "video", "design", "craft", "knit", "knitting", "sew", "sewing",
            "pottery", "art", "compose", "blog", "podcast", "dance", "dancing", "theater",
            "theatre", "calligraphy", "crochet"
        ]
    ]

    static let french: [ItemCategory: [String]] = [
        .fitness: [
            "courir", "course à pied", "footing", "jogging", "sport", "musculation", "muscu",
            "entraînement", "entraîner", "étirement", "natation", "nager", "piscine", "vélo",
            "randonnée", "rando", "marche", "marcher", "pompe", "abdos", "gainage", "yoga",
            "pilates", "cardio", "escalade", "boxe", "tennis", "football", "salle de sport",
            "activité physique"
        ],
        .sleep: [
            "dormir", "sommeil", "sieste", "coucher", "se coucher", "heure du coucher", "lit",
            "au lit", "réveil", "réveiller", "endormir", "insomnie", "oreiller", "dodo",
            "grasse matinée", "couette", "somnoler", "pyjama", "se lever", "mélatonine"
        ],
        .health: [
            "médecin", "docteur", "dentiste", "médicament", "comprimé", "pilule", "vitamine",
            "complément", "pharmacie", "ordonnance", "kiné", "kinésithérapeute",
            "ostéopathe", "prise de sang", "vaccin", "hôpital", "clinique", "infirmière",
            "eau", "hydrater", "régime", "fil dentaire", "dents", "crème solaire",
            "allergie", "santé", "ophtalmo", "légume"
        ],
        .mind: [
            "méditer", "méditation", "pleine conscience", "respirer", "respiration",
            "cohérence cardiaque", "journal", "gratitude", "thérapie", "psy", "psychologue",
            "relaxation", "détendre", "calme", "prière", "prier", "humeur", "anxiété",
            "déconnexion", "sophrologie", "bien-être", "introspection", "lire un livre"
        ],
        .study: [
            "étudier", "étude", "devoir", "examen", "partiel", "réviser", "révision", "cours",
            "classe", "leçon", "professeur", "prof", "enseignant", "école", "université", "fac",
            "lycée", "collège", "mémoire", "doctorat", "exposé", "apprendre", "élève",
            "étudiant", "bac", "concours", "maths", "physique", "chimie", "biologie",
            "grammaire", "vocabulaire"
        ],
        .work: [
            "travail", "travailler", "boulot", "réunion", "mail", "courriel", "diapo",
            "rapport", "projet", "patron", "collègue", "bureau", "entretien", "devis",
            "tableur", "dossier", "compte rendu", "échéance", "contrat", "livrable",
            "télétravail", "stage", "candidature", "atelier", "présentation", "client",
            "conférence", "cv"
        ],
        .money: [
            "payer", "loyer", "facture", "facture d'eau", "banque", "impôt", "taxe", "épargne",
            "économiser", "investir", "investissement", "assurance", "prêt", "crédit",
            "dette", "dépense", "remboursement", "rembourser", "virement", "salaire",
            "comptable", "compte", "argent", "abonnement", "paiement", "mutuelle", "finances",
            "budget"
        ],
        .home: [
            "ménage", "nettoyer", "nettoyage", "ranger", "rangement", "lessive", "linge",
            "vaisselle", "aspirateur", "serpillière", "poussière", "cuisine", "salle de bain",
            "jardin", "jardinage", "plante", "arroser", "cuisiner", "repas", "poubelle",
            "recyclage", "bricolage", "réparer", "repasser", "frigo", "fenêtre", "maison",
            "appartement", "meuble", "tondre", "pelouse", "déménagement", "désencombrer",
            "travaux"
        ],
        .errands: [
            "courses", "faire les courses", "faire des courses", "liste de courses", "acheter",
            "achat", "supermarché", "magasin", "épicerie", "poste", "bureau de poste", "colis",
            "récupérer", "déposer", "coiffeur", "pressing", "essence",
            "garage", "mécanicien", "papiers", "paperasse", "démarche", "passeport", "permis",
            "renouveler", "commande", "boulangerie"
        ],
        .social: [
            "appeler", "maman", "papa", "mère", "père", "famille", "ami", "amie", "copain",
            "copine", "anniversaire", "fête", "soirée", "dîner", "déjeuner", "mariage",
            "visite", "rendre visite", "mamie", "papi", "grand-mère", "grand-père", "frère",
            "sœur", "soeur", "enfant", "fils", "fille", "mari", "femme", "voisin", "inviter",
            "cadeau", "texto", "apéro", "prendre des nouvelles"
        ],
        .creative: [
            "guitare", "violon", "musique", "chanson", "chanter", "chorale", "dessin",
            "dessiner", "peinture", "peindre", "croquis", "écrire", "écriture", "roman",
            "poème", "poésie", "photographie", "vidéo", "montage", "tricot", "tricoter",
            "couture", "coudre", "poterie", "céramique", "composer", "danse", "danser",
            "théâtre", "aquarelle", "solfège", "calligraphie", "piano"
        ]
    ]
}
