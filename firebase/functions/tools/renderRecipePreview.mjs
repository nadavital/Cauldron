import { writeFile } from "node:fs/promises";
import { generateRecipePageHtml, sanitizeRecipeShareInput } from "../lib/index.js";

const outputPath = process.argv[2] || "/tmp/cauldron-recipe-preview.html";
const fixture = sanitizeRecipeShareInput({
    recipeId: "018f9344-54ff-42fc-83a8-c2a92e2d1b10",
    ownerId: "9f082214-0c9e-4e30-94d7-072fc359d2f4",
    identityRecordName: "user_current-user-record",
    title: "Fire-Roasted Tomato Soup",
    ingredientCount: 8,
    totalMinutes: 50,
    tags: ["Dinner", "Vegetarian", "Comfort Food"],
    yields: "4 generous bowls",
    notes: "Roasting the tomatoes first gives this soup its deep, smoky sweetness. A final swirl of olive oil makes it sing.",
    sourceTitle: "The Cauldron Kitchen",
    sourceURL: "https://example.com/fire-roasted-tomato-soup",
    authorName: "Nadav",
    originalCreatorName: "Mara's Kitchen",
    capability: "q".repeat(43),
    ingredients: [
        { text: "2 pounds ripe tomatoes, halved", section: "For the soup" },
        { text: "1 yellow onion, roughly chopped", section: "For the soup" },
        { text: "5 garlic cloves", section: "For the soup" },
        { text: "2 tablespoons extra-virgin olive oil", section: "For the soup" },
        { text: "2 cups vegetable stock", section: "To finish" },
        { text: "1 small handful fresh basil", section: "To finish" },
        { text: "Sea salt and cracked black pepper", section: "To finish" },
        { text: "Crème fraîche, optional", section: "To finish" },
    ],
    steps: [
        { text: "Heat the oven to 425°F. Arrange the tomatoes, onion, and garlic on a rimmed tray. Drizzle with olive oil and season generously.", section: "Roast" },
        { text: "Roast until the tomatoes collapse and their edges begin to char, 30–35 minutes.", section: "Roast" },
        { text: "Transfer everything to a pot, add the stock, and simmer gently for 10 minutes.", section: "Blend" },
        { text: "Blend until velvety. Fold in the basil, taste, and adjust the seasoning.", section: "Blend" },
        { text: "Ladle into warm bowls and finish with olive oil and crème fraîche.", section: "Serve" },
    ],
});

if (!fixture.ok) {
    throw new Error(fixture.error);
}

const html = generateRecipePageHtml(
    fixture.value,
    "https://cauldron-f900a.web.app/recipe/018f9344-54ff-42fc-83a8-c2a92e2d1b10",
    "cauldron://import/recipe/018f9344-54ff-42fc-83a8-c2a92e2d1b10",
    "https://apps.apple.com/us/app/cauldron-magical-recipes/id6754004943"
);
await writeFile(outputPath, html, "utf8");
console.log(outputPath);
