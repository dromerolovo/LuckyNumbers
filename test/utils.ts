
export function areAllElementsUnique(arr: any[]): boolean {
    return arr.length === new Set(arr).size;
  }

export function delay(ms: number) {
    return new Promise( resolve => setTimeout(resolve, ms) );
}