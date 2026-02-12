# Holdout Candidate URLs (Fixed Eval Set)

Date curated: 2026-02-11  
Validation status: all URLs below returned HTTP 200 on 2026-02-11 with a browser user-agent.

Use this as a fixed eval-only set after freezing (do not train on these once frozen).

## Known labeled URLs to avoid in holdout v1

These already appear in your current labeled set/workflow and should stay out of the frozen holdout:

- https://downshiftology.com/recipes/shakshuka/
- https://www.halfbakedharvest.com/honey-garlic-chicken/
- https://www.delish.com/cooking/recipe-ideas/a60204088/chicken-and-broccoli-recipe/
- https://www.inspiredtaste.net/15938/easy-and-smooth-hummus-recipe/
- https://www.loveandlemons.com/broccolini/
- https://www.thekitchn.com/how-to-make-congee-226778

## Proposed frozen holdout v1 (24 URLs)

1. https://www.smittenkitchen.com/2025/05/one-pan-ditalini-and-peas/
2. https://www.smittenkitchen.com/2025/02/ziti-chickpeas-with-sausage-and-kale/
3. https://www.smittenkitchen.com/2025/10/baked-potatoes-with-crispy-broccoli-and-bacon/
4. https://www.smittenkitchen.com/2025/08/double-chocolate-zucchini-bread/
5. https://www.recipetineats.com/quick-and-dirty-focaccia/
6. https://www.recipetineats.com/chicken-pad-thai/
7. https://www.recipetineats.com/thai-stir-fried-noodles-pad-see-ew/
8. https://www.recipetineats.com/pad-kee-mao-thai-drunken-noodles/
9. https://www.inspiredtaste.net/97738/chicken-pot-pie-recipe/
10. https://www.inspiredtaste.net/98468/beef-bulgogi-recipe/
11. https://www.inspiredtaste.net/64999/glazed-salmon/
12. https://www.inspiredtaste.net/47852/roasted-broccolini/
13. https://www.downshiftology.com/recipes/red-lentil-soup/
14. https://www.downshiftology.com/recipes/shepherds-pie/
15. https://www.downshiftology.com/recipes/meatloaf/
16. https://www.cookieandkate.com/black-bean-sweet-potato-enchiladas/
17. https://www.cookieandkate.com/kale-apple-salad-with-granola-croutons/
18. https://www.cookieandkate.com/sweet-potato-red-pepper-feta-frittata/
19. https://www.kingarthurbaking.com/recipes/no-knead-crusty-white-bread-recipe
20. https://www.kingarthurbaking.com/recipes/flourless-chocolate-cake-recipe
21. https://www.sallysbakingaddiction.com/vanilla-sheet-cake/
22. https://www.bbcgoodfood.com/recipes/feta-roasted-tomato-shakshuka
23. https://www.seriouseats.com/the-best-chili-recipe
24. https://thewoksoflife.com/hot-sour-soup/

## Optional expansion pool (20 URLs)

1. https://www.smittenkitchen.com/2026/01/simple-crispy-pan-pizza/
2. https://www.recipetineats.com/focaccia-recipe/
3. https://www.downshiftology.com/recipes/ceviche/
4. https://www.downshiftology.com/recipes/lemon-vinaigrette/
5. https://www.cookieandkate.com/honey-almond-granola/
6. https://www.kingarthurbaking.com/recipes/perfectly-pillowy-cinnamon-rolls-recipe
7. https://www.kingarthurbaking.com/recipes/no-fuss-focaccia-recipe
8. https://www.kingarthurbaking.com/recipes/giant-cinnamon-roll-recipe
9. https://www.kingarthurbaking.com/recipes/golden-focaccia-recipe
10. https://www.sallysbakingaddiction.com/coconut-cake/
11. https://www.sallysbakingaddiction.com/2013/03/11/super-moist-carrot-cake/
12. https://www.bbcgoodfood.com/recipes/hummus
13. https://www.seriouseats.com/ultra-crispy-slow-roasted-pork-shoulder-recipe
14. https://www.simplyrecipes.com/recipes/banana_bread/
15. https://www.simplyrecipes.com/recipes/spaghetti_alla_carbonara/
16. https://www.allrecipes.com/recipe/10813/best-chocolate-chip-cookies/
17. https://www.allrecipes.com/recipe/24074/alysias-basic-meat-lasagna/
18. https://www.budgetbytes.com/easy-sesame-chicken/
19. https://www.budgetbytes.com/chicken-fried-rice/
20. https://thewoksoflife.com/beef-oyster-sauce/

## Freezing protocol

1. Import + label-correct only the 24 v1 URLs above.
2. Save them with a dedicated id prefix (for example, `holdout_*`).
3. Keep holdout fixtures out of retraining exports.
4. Run metrics on this same frozen set after every retrain so trend lines are comparable.
