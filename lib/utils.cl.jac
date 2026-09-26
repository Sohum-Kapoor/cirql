cl import from "clsx" { clsx }
cl import from "tailwind-merge" { extendTailwindMerge }

# DESIGN.md type tokens (assets/main.css @theme --text-*) are font sizes, not
# colours: without this, twMerge files `text-eyebrow` under text-color and drops
# it next to `text-muted-foreground` (or vice versa).
glob _twMerge: any = extendTailwindMerge({
         "extend": {
             "theme": {
                 "text": [
                     "display-md", "headline", "card-title", "subhead", "body-lg", "body",
                     "body-sm", "caption", "button", "eyebrow", "mono"
                 ],
                 "shadow": ["edge"]
             }
         }
     });

def:pub cn(*inputs: any) -> any {
    return _twMerge(clsx(inputs));
}
