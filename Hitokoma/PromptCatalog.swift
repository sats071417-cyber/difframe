import Foundation

/// お題の一覧。すべて、iPhoneの画像認識（Vision）が見分けられる言葉に対応している。
/// 対応する言葉は、iPhoneが持つ認識の言葉（約1300種）の名前そのまま。
/// 色・形・質感のように、画像認識が見分けられないものは入れない。
enum PromptCatalog {
    static let entries: [(prompt: String, labels: [String])] = [
        ("服", ["clothing", "jacket", "hoodie", "jeans"]),
        ("時計", ["clock", "watch", "timepiece", "stopwatch"]),
        ("椅子", ["chair", "chair_other", "folding_chair", "swivel_chair", "armchair"]),
        ("リュック", ["backpack", "bag"]),
        ("ジュース", ["juice", "smoothie", "soda"]),
        ("靴", ["shoes", "footwear", "sneaker", "boot", "sandal", "loafer", "high_heel"]),
        ("財布", ["wallet", "purse"]),
        ("ご飯", ["rice", "food", "strawberry", "hamburger", "cookie", "ramen", "butter", "bread", "white_bread", "bagel", "baked_goods", "egg", "fried_egg", "soup", "pudding", "sausage", "grape", "banana", "cake", "cupcake", "birthday_cake", "cake_regular", "pancake", "oranges", "citrus_fruit", "ice_cream", "frozen_dessert", "popsicle", "cheese", "mushroom", "corn", "chocolate", "broccoli", "cucumber", "popcorn", "nut", "lemon", "carrot", "salad", "pasta", "spaghetti", "chewing_gum", "sandwich", "pizza", "tomato", "potato", "onion", "yogurt", "honey", "donut"]),
        ("コーヒー", ["coffee", "mug", "cup"]),
        ("鞄", ["bag", "backpack", "briefcase", "purse", "suitcase", "luggage"]),
        ("窓", ["window"]),
        ("空", ["sky"]),
        ("木", ["tree"]),
        ("花", ["flower"]),
        ("階段", ["stairs"]),
        ("建物", ["building"]),
        ("道", ["street"]),
        ("飲み物の容器", ["bottle", "thermos"]),
        ("イヤホン・ヘッドホン", ["headphones"]),
        ("車", ["car", "automobile", "suv", "jeep", "sportscar"]),
        ("自転車", ["bicycle"]),
        ("ペット", ["cat", "kitten", "dog", "rabbit", "hamster", "goldfish", "parrot", "turtle"]),
        ("鳥", ["bird", "parrot", "pigeon", "owl"]),
        ("標識", ["street_sign", "sign"]),
        ("広告看板", ["billboards", "banner"]),
        ("ボール", ["ball", "basketball", "football", "soccer", "baseball", "volleyball", "golf_ball"]),
        ("スポーツ", ["sport", "ballgames", "athletics", "winter_sport", "watersport", "soccer", "basketball", "baseball", "football", "tennis", "volleyball", "golf", "rugby", "skateboarding", "skiing", "snowboarding", "surfing", "cycling", "swimming", "boxing"]),
        ("アート", ["art", "painting", "illustrations", "graffiti", "statue", "stained_glass", "figurine", "origami"]),
        ("乗り物", ["vehicle", "conveyance", "car", "automobile", "bus", "train", "bicycle", "motorcycle", "truck", "airplane", "aircraft", "boat", "scooter", "tricycle", "van"]),
        ("家電", ["appliance", "consumer_electronics", "refrigerator", "microwave", "laundry_machine", "electric_fan", "toaster", "toaster_oven", "vacuum", "dishwasher", "television", "kitchen_oven", "blender", "juicer"]),
        ("机", ["desk", "table"]),
        ("家具", ["furniture", "chair", "chair_other", "armchair", "sofa", "bed", "bookshelf", "cabinet", "table", "desk", "stool", "bench", "chaise"]),
        ("街灯", ["lamppost"]),
        ("クリスマスの物", ["christmas_decoration", "christmas_tree", "wreath", "candy_cane", "gift"]),
        ("食器", ["tableware", "utensil", "plate", "bowl", "cup", "mug", "drinking_glass", "fork", "spoon", "knife", "chopsticks"]),
        ("お金", ["money", "currency", "coin"]),
        ("ぬいぐるみ", ["stuffed_animals"]),
        ("落書き", ["graffiti"]),
        ("信号機", ["traffic_light"]),
        ("マンホール", ["manhole"]),
        ("ドア", ["door"]),
    ]

    /// お題の一覧
    /// 色のお題。iPhoneの画像認識は色を見分けられないので、写真の色の割合を数えて確かめる（PromptVerifier の ColorMatcher）。
    static let colorEntries: [(prompt: String, color: ColorName)] = [
        ("赤いもの", .red), ("青いもの", .blue), ("緑のもの", .green), ("黄色いもの", .yellow),
        ("オレンジのもの", .orange), ("紫のもの", .purple), ("ピンクのもの", .pink),
        ("白いもの", .white), ("黒いもの", .black), ("茶色のもの", .brown),
    ]

    static let colors: [String: ColorName] = Dictionary(uniqueKeysWithValues: colorEntries.map { ($0.prompt, $0.color) })

    static let prompts: [String] = entries.map(\.prompt) + colorEntries.map(\.prompt)

    /// お題ごとの、画像認識の言葉
    static let labels: [String: [String]] = Dictionary(uniqueKeysWithValues: entries.map { ($0.prompt, $0.labels) })
}


enum ColorName { case red, orange, yellow, green, blue, purple, pink, brown, white, black }
