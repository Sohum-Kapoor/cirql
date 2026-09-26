cl import from "clsx" { clsx }
cl import from "tailwind-merge" { twMerge }

def:pub cn(*inputs: any) -> any {
    return twMerge(clsx(inputs));
}
