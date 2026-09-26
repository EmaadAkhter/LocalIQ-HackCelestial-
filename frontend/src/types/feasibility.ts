export interface FeasibilityScore {
  score: number;
  factors: Record<string, number>;
}

export interface Recommendation {
  id: string;
  title: string;
  description: string;
  feasibility: FeasibilityScore;
}