import * as React from "react";
import { cva, type VariantProps } from "class-variance-authority";
import { cn } from "@/lib/utils";

const alertVariants = cva(
  "relative grid w-full grid-cols-[auto_1fr] items-start gap-3 rounded-lg border px-4 py-3 text-sm",
  {
    defaultVariants: {
      variant: "default"
    },
    variants: {
      variant: {
        default: "bg-card text-card-foreground",
        destructive: "border-destructive/35 bg-destructive/10 text-destructive"
      }
    }
  }
);

export interface AlertProps
  extends React.HTMLAttributes<HTMLDivElement>,
    VariantProps<typeof alertVariants> {}

export function Alert({ className, variant, ...props }: AlertProps) {
  return <div className={cn(alertVariants({ className, variant }))} role="alert" {...props} />;
}

export function AlertTitle({ className, ...props }: React.HTMLAttributes<HTMLDivElement>) {
  return <div className={cn("font-medium leading-none", className)} {...props} />;
}

export function AlertDescription({ className, ...props }: React.HTMLAttributes<HTMLDivElement>) {
  return <div className={cn("mt-1 text-sm leading-5 opacity-90", className)} {...props} />;
}
