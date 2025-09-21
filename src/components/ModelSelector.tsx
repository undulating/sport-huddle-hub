// src/components/ModelSelector.tsx
// Updated to work with string model IDs and display model info

import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Info } from "lucide-react";
import {
    Tooltip,
    TooltipContent,
    TooltipProvider,
    TooltipTrigger,
} from "@/components/ui/tooltip";

export interface ModelInfo {
    id: string;
    name: string;
    description: string;
    accuracy: number;
    historical_accuracy: number;
    version: string;
}

interface ModelSelectorProps {
    selectedModel: string;  // Changed from number to string
    onModelChange: (model: string) => void;  // Changed from number to string
    models?: ModelInfo[];  // Optional array of available models
}

export const ModelSelector = ({
    selectedModel,
    onModelChange,
    models = []
}: ModelSelectorProps) => {
    // Default models if none provided
    const defaultModels: ModelInfo[] = [
        {
            id: 'elo',
            name: 'Standard Elo',
            description: 'Traditional Elo rating system',
            accuracy: 0.848,
            historical_accuracy: 0.625,
            version: '1.0.0'
        },
        {
            id: 'elo_recent',
            name: 'Elo with Recent Form',
            description: 'Elo ratings with 30% weight on last 3 games',
            accuracy: 0.830,
            historical_accuracy: 0.635,
            version: '1.0.0'
        }
    ];

    const availableModels = models.length > 0 ? models : defaultModels;
    const currentModel = availableModels.find(m => m.id === selectedModel);

    return (
        <div className="flex items-center gap-2">
            <span className="text-sm font-medium text-muted-foreground">Model:</span>
            <Select value={selectedModel} onValueChange={onModelChange}>
                <SelectTrigger className="w-[200px]">
                    <SelectValue placeholder="Select a model" />
                </SelectTrigger>
                <SelectContent>
                    {availableModels.map((model) => (
                        <SelectItem key={model.id} value={model.id}>
                            <div className="flex items-center justify-between w-full">
                                <span>{model.name}</span>

                            </div>
                        </SelectItem>
                    ))}
                </SelectContent>
            </Select>

            {currentModel && (
                <TooltipProvider>
                    <Tooltip>
                        <TooltipTrigger asChild>
                            <Info className="h-4 w-4 text-muted-foreground cursor-help" />
                        </TooltipTrigger>
                        <TooltipContent className="max-w-xs">
                            <div className="space-y-2">
                                <p className="font-semibold">{currentModel.name}</p>
                                <p className="text-sm">{currentModel.description}</p>
                                <div className="text-xs space-y-1 pt-2 border-t">
                                    <div>2025 Accuracy: {(currentModel.accuracy * 100).toFixed(1)}%</div>
                                    <div>Historical: {(currentModel.historical_accuracy * 100).toFixed(1)}%</div>
                                    <div>Version: {currentModel.version}</div>
                                </div>
                            </div>
                        </TooltipContent>
                    </Tooltip>
                </TooltipProvider>
            )}
        </div>
    );
};